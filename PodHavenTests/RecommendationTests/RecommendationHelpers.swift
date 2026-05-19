// Copyright Justin Bishop, 2026

import AVFoundation
import FactoryKit
import Foundation
import Testing

@testable import PodHaven

enum RecommendationHelpers {
  // MARK: - Dependency Access

  private static var engine: RecommendationEngine { Container.shared.recommendationEngine() }
  private static var repo: any Databasing { Container.shared.repo() }

  // MARK: - Fixture Builders

  static func createPodcastWithEpisodes(
    count: Int,
    podcastTitle: String = String.random(),
    podcastDescription: String = String.random(),
    episodeDescriptions: [String]? = nil,
    ratings: [EpisodeRating?]? = nil,
    finished: [Bool]? = nil,
    pubDateOffset: (Int) -> TimeInterval = { i in TimeInterval(-i * 86400) }
  ) async throws -> (podcast: Podcast, episodes: [Episode]) {
    let unsavedPodcast = try Create.unsavedPodcast(
      title: podcastTitle,
      description: podcastDescription
    )

    let unsavedEpisodes = try (0..<count)
      .map { i in
        try buildUnsaved(
          index: i,
          podcastTitle: podcastTitle,
          episodeDescriptions: episodeDescriptions,
          ratings: ratings,
          finished: finished,
          pubDateOffset: pubDateOffset
        )
      }
    let entries = unsavedEpisodes.map {
      UnsavedPodcastEpisode(unsavedPodcast: unsavedPodcast, unsavedEpisode: $0)
    }

    let podcastEpisodes = try await repo.upsertPodcastEpisodes(entries)
    let podcast = try #require(podcastEpisodes.first?.podcast)
    return (podcast, podcastEpisodes.map(\.episode))
  }

  // Adds new episodes to an existing podcast — useful for testing podcast-level
  // behavior (affinity, candidate filtering) where signals and candidates need
  // to share a podcast row.
  static func addEpisodes(
    to podcast: Podcast,
    count: Int,
    episodeDescriptions: [String]? = nil,
    ratings: [EpisodeRating?]? = nil,
    finished: [Bool]? = nil,
    pubDateOffset: (Int) -> TimeInterval = { i in TimeInterval(-i * 86400) }
  ) async throws -> [Episode] {
    let unsavedPodcast = try Create.unsavedPodcast(
      feedURL: podcast.feedURL,
      title: podcast.title,
      image: podcast.image,
      description: podcast.description
    )

    let unsavedEpisodes = try (0..<count)
      .map { i in
        try buildUnsaved(
          index: i,
          podcastTitle: podcast.title,
          episodeDescriptions: episodeDescriptions,
          ratings: ratings,
          finished: finished,
          pubDateOffset: pubDateOffset
        )
      }
    let entries = unsavedEpisodes.map {
      UnsavedPodcastEpisode(unsavedPodcast: unsavedPodcast, unsavedEpisode: $0)
    }

    let podcastEpisodes = try await repo.upsertPodcastEpisodes(entries)
    return podcastEpisodes.map(\.episode)
  }

  private static func buildUnsaved(
    index i: Int,
    podcastTitle: String,
    episodeDescriptions: [String]?,
    ratings: [EpisodeRating?]?,
    finished: [Bool]?,
    pubDateOffset: (Int) -> TimeInterval
  ) throws -> UnsavedEpisode {
    let rating = ratings?[safe: i] ?? nil
    let isFinished = finished?[safe: i] ?? false
    let description = episodeDescriptions?[safe: i] ?? "Episode \(i) description"
    return try Create.unsavedEpisode(
      title: "Episode \(i) of \(podcastTitle)",
      pubDate: Date().addingTimeInterval(pubDateOffset(i)),
      duration: CMTime(seconds: 1800, preferredTimescale: 1),
      description: description,
      finishDate: isFinished ? Date() : nil,
      rating: rating,
      ratingDate: rating != nil ? Date() : nil
    )
  }

  static func embedEpisodes(
    _ episodes: [Episode],
    embeddable: any Embeddable & Sendable = FakeEmbeddable()
  ) async throws {
    let embedding = ContextualEmbedding(embedding: embeddable)
    await embedding.requestAndLoadAssetsIfNeeded()
    try await EmbeddingService.upsertEpisodeEmbeddings(
      for: episodes,
      embedding: embedding
    )
  }

  // MARK: - Engine Drivers

  // The engine spawns its observation Task on `start()` and only populates
  // its cache once the Observatory has emitted. Tests for "expected
  // non-empty" results poll until the cache lands; tests for "expected
  // empty" results don't need to wait since both cold and hot states yield
  // empty.
  static func startAndWaitForRecs() async throws -> [RankedRecommendation] {
    let engine = self.engine
    engine.start()
    return try await waitAdvancing {
      let recs = try await engine.topRecommendations()
      return recs.isEmpty ? nil : recs
    }
  }

  static func startAndWaitForScores(
    for episodes: [Episode]
  ) async throws -> [Episode.ID: RecommendationScore] {
    let engine = self.engine
    engine.start()
    return try await waitAdvancing {
      let map = try await engine.recommendations(for: episodes)
      return map.isEmpty ? nil : map
    }
  }

  // The engine batches cache rebuilds through a 400ms Debounce. New triggers
  // can land at any time during the test, each cancelling the prior sleep
  // and arming a fresh one (FakeSleeper requires manual advance). Polling
  // with a per-iteration advance fires whatever sleep is currently armed
  // and cleanly handles the case where another rebuild gets scheduled
  // after a previous one already fired.
  static func waitAdvancing<T: Sendable>(
    _ block: @Sendable @escaping () async throws -> T?
  ) async throws -> T {
    let sleeper = Container.shared.sleeper() as! FakeSleeper
    return try await Wait.forValue {
      await sleeper.advanceTime(by: .milliseconds(400))
      return try await block()
    }
  }

  // Same per-iteration FakeSleeper advance as `waitAdvancing`, but for the
  // boolean-condition + error-message shape of `Wait.until`. Use whenever a
  // VM-level effect is gated on the engine's debounced contextRevision tick.
  static func untilAdvancing(
    priority: TaskPriority = .background,
    _ block: @Sendable @escaping () async throws -> Bool,
    _ errorMessage: @Sendable @escaping () async throws -> String
  ) async throws {
    let sleeper = Container.shared.sleeper() as! FakeSleeper
    try await Wait.until(
      priority: priority,
      {
        await sleeper.advanceTime(by: .milliseconds(400))
        return try await block()
      },
      errorMessage
    )
  }
}
