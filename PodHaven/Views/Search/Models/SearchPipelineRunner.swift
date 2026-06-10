// Copyright Justin Bishop, 2026

import CoreMedia
import FactoryKit
import Foundation
import Logging

// MARK: - SearchPipelineRunner

// Fetch → parse → filter → embed → score for a single podcast feed. Owns no
// cache state, so the collector stays "schedule + cache + post-process."
enum SearchPipelineRunner {
  private static let log = Log.as(LogSubsystem.SearchView.recommendations)

  // MARK: - Tunable Caps

  static let episodesPerPodcast = 10

  // Discovery removes freshness, so neutral content clusters around 0.5.
  static let scoreFloor: Float = 0.5

  // MARK: - Pipeline Result

  enum PipelineResult {
    case success([ScoredEpisode])
    case cancelled
    case failed(any Error)
  }

  // MARK: - Pipeline

  static func run(
    feedURL: FeedURL,
    downloadTask: DownloadTask,
    podcastID: Podcast.ID?,
    iTunesID: ITunesPodcastID?,
    onDeckID: Episode.ID?,
    isDetached: @Sendable () async -> Bool
  ) async -> PipelineResult {
    let embedding = Container.shared.contextualEmbedding()
    let engine = Container.shared.recommendationEngine()
    let repo = Container.shared.repo()

    let feedData: DownloadData
    do {
      feedData = try await downloadTask.downloadFinished()
    } catch is CancellationError {
      return .cancelled
    } catch {
      return .failed(error)
    }

    if Task.isCancelled { return .cancelled }

    let podcastFeed: PodcastFeed
    do {
      podcastFeed = try await PodcastFeed.parse(feedData)
    } catch {
      return .failed(error)
    }

    let unsavedPodcast: UnsavedPodcast
    do {
      unsavedPodcast = try podcastFeed.toUnsavedPodcast(iTunesID: iTunesID)
    } catch {
      return .failed(error)
    }

    let newest = Array(
      podcastFeed.toUnsavedEpisodes()
        .sorted { $0.pubDate > $1.pubDate }
        .prefix(episodesPerPodcast)
    )
    let candidates: [UnsavedEpisode]
    do {
      candidates = try await filteredCandidates(
        newest: newest,
        podcastID: podcastID,
        onDeckID: onDeckID,
        repo: repo
      )
    } catch {
      return .failed(error)
    }

    if Task.isCancelled { return .cancelled }

    var payloads = [UnsavedPodcastEpisode](capacity: candidates.count)
    var vectors = [[Float]](capacity: candidates.count)
    for unsavedEpisode in candidates {
      if Task.isCancelled { return .cancelled }
      if await isDetached() { return .cancelled }
      let payload = UnsavedPodcastEpisode(
        unsavedPodcast: unsavedPodcast,
        unsavedEpisode: unsavedEpisode
      )
      do {
        let vector = try await EmbeddingService.embeddingVector(for: payload, embedding: embedding)
        payloads.append(payload)
        vectors.append(vector)
      } catch is CancellationError {
        return .cancelled
      } catch {
        log.caughtError(
          "Embedding failed for \(payload.toString); skipping",
          error,
          level: { _ in .info }
        )
      }
    }

    if Task.isCancelled { return .cancelled }
    if await isDetached() { return .cancelled }

    let similarities: [Float?]
    do {
      similarities = try await engine.similarityScores(forEmbeddings: vectors)
    } catch is CancellationError {
      return .cancelled
    } catch {
      return .failed(error)
    }

    var scored = [ScoredEpisode](capacity: payloads.count)
    for (payload, score) in zip(payloads, similarities) {
      guard let score, score > scoreFloor else { continue }
      scored.append(ScoredEpisode(feedURL: feedURL, episode: payload, score: score))
    }

    return .success(scored)
  }

  // Drops episodes whose existing DB row fails the candidate gate. Unreconciled
  // podcasts (no DB row) pass through unchanged.
  private static func filteredCandidates(
    newest: [UnsavedEpisode],
    podcastID: Podcast.ID?,
    onDeckID: Episode.ID?,
    repo: any Databasing
  ) async throws -> [UnsavedEpisode] {
    guard let podcastID, !newest.isEmpty else { return newest }
    let existing = try await repo.episodesMatching(
      podcastID: podcastID,
      guids: newest.map(\.guid),
      mediaURLs: newest.map(\.mediaURL)
    )

    let existingByGUID = Dictionary(uniqueKeysWithValues: existing.map { ($0.guid, $0) })
    let existingByMediaURL = Dictionary(uniqueKeysWithValues: existing.map { ($0.mediaURL, $0) })

    var result = [UnsavedEpisode](capacity: newest.count)
    for unsaved in newest {
      let match = existingByGUID[unsaved.guid] ?? existingByMediaURL[unsaved.mediaURL]
      if let match, !isDiscoveryCandidate(match, excludingOnDeck: onDeckID) {
        continue
      }
      result.append(unsaved)
    }
    return result
  }

  // Also the live re-gate predicate for SearchDiscoveryListViewModel's
  // saved-row observation, which drops picks whose materialized row stops
  // qualifying (e.g. queued or rated from the detail screen).
  static func isDiscoveryCandidate(
    _ episode: some EpisodeFoundational,
    excludingOnDeck onDeckID: Episode.ID?
  ) -> Bool {
    if let onDeckID, episode.episodeID == onDeckID { return false }
    return episode.isCandidate
  }
}
