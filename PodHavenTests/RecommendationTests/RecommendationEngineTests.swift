// Copyright Justin Bishop, 2026

import AVFoundation
import FactoryKit
import FactoryTesting
import Foundation
import GRDB
import Testing

@testable import PodHaven

@Suite("RecommendationEngine tests", .container)
class RecommendationEngineTests {
  @DynamicInjected(\.recommendationEngine) private var engine
  @DynamicInjected(\.repo) private var repo

  // MARK: - Helpers

  private func createPodcastWithEpisodes(
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
  private func addEpisodes(
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

  private func buildUnsaved(
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

  private func embedEpisodes(
    _ episodes: [Episode],
    embeddable: any Embeddable = FakeEmbeddable()
  ) async throws {
    let embedding = ContextualEmbedding(embedding: embeddable)
    embedding.requestAndLoadAssetsIfNeeded()
    try await EmbeddingService.upsertEpisodeEmbeddings(
      for: episodes,
      embedding: embedding
    )
  }

  // MARK: - Minimum Threshold

  @Test("returns empty when fewer than 3 signal episodes")
  func minimumThreshold() async throws {
    let (_, episodes) = try await createPodcastWithEpisodes(
      count: 2,
      ratings: [.loved, .liked]
    )
    try await embedEpisodes(episodes)

    let recommendations = try await engine.topRecommendations()
    #expect(recommendations.isEmpty)
  }

  // MARK: - Basic Recommendations

  @Test("returns recommendations when threshold is met")
  func basicRecommendations() async throws {
    // Create rated episodes (signal)
    let (_, signalEpisodes) = try await createPodcastWithEpisodes(
      count: 3,
      podcastTitle: "Signal Podcast",
      ratings: [.loved, .liked, .liked]
    )
    try await embedEpisodes(signalEpisodes)

    // Create candidate episodes (unrated, unfinished, unqueued)
    let (_, candidateEpisodes) = try await createPodcastWithEpisodes(
      count: 3,
      podcastTitle: "Candidate Podcast"
    )
    try await embedEpisodes(candidateEpisodes)

    let recommendations = try await engine.topRecommendations()
    #expect(!recommendations.isEmpty)
    #expect(recommendations.count <= 10)

    // Verify deterministic ordering (scores should be descending)
    for i in 0..<(recommendations.count - 1) {
      #expect(recommendations[i].score.score >= recommendations[i + 1].score.score)
    }
  }

  // MARK: - Candidate Filtering

  @Test("excludes finished episodes from candidates")
  func excludesFinished() async throws {
    let (_, signalEpisodes) = try await createPodcastWithEpisodes(
      count: 3,
      podcastTitle: "Signal",
      ratings: [.loved, .liked, .liked]
    )
    try await embedEpisodes(signalEpisodes)

    let (_, candidates) = try await createPodcastWithEpisodes(
      count: 2,
      podcastTitle: "Candidates",
      finished: [true, false]
    )
    try await embedEpisodes(candidates)

    let recommendations = try await engine.topRecommendations()
    let recommendedIDs = Set(recommendations.map(\.episode.id))

    #expect(!recommendedIDs.contains(candidates[0].id))
  }

  @Test("excludes rated episodes from candidates")
  func excludesRated() async throws {
    let (_, signalEpisodes) = try await createPodcastWithEpisodes(
      count: 3,
      podcastTitle: "Signal",
      ratings: [.loved, .liked, .liked]
    )
    try await embedEpisodes(signalEpisodes)

    let (_, rated) = try await createPodcastWithEpisodes(
      count: 1,
      podcastTitle: "Rated Candidate",
      ratings: [.disliked]
    )
    try await embedEpisodes(rated)

    let recommendations = try await engine.topRecommendations()
    let recommendedIDs = Set(recommendations.map(\.episode.id))
    #expect(!recommendedIDs.contains(rated[0].id))
  }

  // MARK: - All Disliked

  @Test("handles all-disliked history gracefully")
  func allDisliked() async throws {
    _ = try await createPodcastWithEpisodes(
      count: 3,
      podcastTitle: "Disliked",
      ratings: [.disliked, .disliked, .disliked]
    )

    let (_, candidates) = try await createPodcastWithEpisodes(
      count: 2,
      podcastTitle: "Candidates"
    )
    try await embedEpisodes(candidates)

    // Should return empty since there's no positive centroid
    let recommendations = try await engine.topRecommendations()
    #expect(recommendations.isEmpty)
  }

  // MARK: - Reasons

  @Test("recommendations include reasons")
  func recommendationsHaveReasons() async throws {
    let (_, signalEpisodes) = try await createPodcastWithEpisodes(
      count: 3,
      podcastTitle: "Signal",
      ratings: [.loved, .liked, .liked]
    )
    try await embedEpisodes(signalEpisodes)

    let (_, candidates) = try await createPodcastWithEpisodes(
      count: 2,
      podcastTitle: "Candidates"
    )
    try await embedEpisodes(candidates)

    let recommendations = try await engine.topRecommendations()
    for rec in recommendations {
      #expect(!rec.score.reasons.isEmpty)
    }
  }

  // MARK: - New reasons semantics

  @Test("year-old episodes don't include recentlyPublished reason")
  func oldEpisodesExcludeFreshnessReason() async throws {
    let (_, signals) = try await createPodcastWithEpisodes(
      count: 3,
      podcastTitle: "Signal",
      ratings: [.loved, .liked, .liked]
    )
    try await embedEpisodes(signals)

    // Freshness at 365 days with 60-day half-life ≈ 0.14, below the 0.5 threshold.
    let (_, old) = try await createPodcastWithEpisodes(
      count: 1,
      podcastTitle: "Archive",
      pubDateOffset: { _ in TimeInterval(-365 * 86400) }
    )
    try await embedEpisodes(old)

    let recs = try await engine.topRecommendations()
    let oldRec = try #require(recs.first { $0.episode.id == old.first?.id })
    #expect(!oldRec.score.reasons.contains(.recentlyPublished))
  }

  @Test("candidates from an unknown podcast don't include podcastAffinity reason")
  func unknownPodcastExcludesAffinityReason() async throws {
    let (_, signals) = try await createPodcastWithEpisodes(
      count: 3,
      podcastTitle: "Signal",
      ratings: [.loved, .liked, .liked]
    )
    try await embedEpisodes(signals)

    // Candidates live in a podcast with zero positive signals — affinity
    // settles at the neutral 0.5 prior, which must not clear the reason filter.
    let (_, candidates) = try await createPodcastWithEpisodes(
      count: 2,
      podcastTitle: "Unknown"
    )
    try await embedEpisodes(candidates)

    let recs = try await engine.topRecommendations()
    for rec in recs where candidates.map(\.id).contains(rec.episode.id) {
      #expect(!rec.score.reasons.contains(.podcastAffinity))
    }
  }

  @Test("semantically opposite candidates don't include similarToLiked reason")
  func oppositeCandidatesExcludeSimilarityReason() async throws {
    // Engineer vectors so the similarity feature drops well below 0.5 for
    // candidates whose embeddings point the opposite direction from signals.
    let embeddable = ScriptedEmbeddable { text in
      if text.contains("Loved") { return [1, 0, 0] }
      if text.contains("Opposite") { return [-1, 0, 0] }
      return [0, 0, 1]  // neutral filler for podcast descriptions etc.
    }

    let (_, signals) = try await createPodcastWithEpisodes(
      count: 3,
      podcastTitle: "Loved Show",
      podcastDescription: "neutral",
      episodeDescriptions: ["Loved Desc 0", "Loved Desc 1", "Loved Desc 2"],
      ratings: [.loved, .loved, .loved]
    )
    try await embedEpisodes(signals, embeddable: embeddable)

    let (_, opposites) = try await createPodcastWithEpisodes(
      count: 2,
      podcastTitle: "Opposite Show",
      podcastDescription: "neutral",
      episodeDescriptions: ["Opposite Desc 0", "Opposite Desc 1"]
    )
    try await embedEpisodes(opposites, embeddable: embeddable)

    let recs = try await engine.topRecommendations()
    let oppositeIDs = Set(opposites.map(\.id))
    let oppositeRecs = recs.filter { oppositeIDs.contains($0.episode.id) }
    #expect(!oppositeRecs.isEmpty)
    for rec in oppositeRecs {
      #expect(!rec.score.reasons.contains(.similarToLiked))
    }
  }

  @Test("candidates from a loved podcast include podcastAffinity reason")
  func lovedPodcastIncludesAffinityReason() async throws {
    // Three loved episodes on the same podcast drive affinity above neutral.
    let (lovedPodcast, signals) = try await createPodcastWithEpisodes(
      count: 3,
      podcastTitle: "Loved",
      ratings: [.loved, .loved, .loved]
    )
    try await embedEpisodes(signals)

    // Unrated episodes on the SAME podcast are candidates that should carry
    // the affinity reason.
    let candidates = try await addEpisodes(to: lovedPodcast, count: 2)
    try await embedEpisodes(candidates)

    let recs = try await engine.topRecommendations()
    let candidateIDs = Set(candidates.map(\.id))
    let candidateRecs = recs.filter { candidateIDs.contains($0.episode.id) }
    #expect(!candidateRecs.isEmpty)
    for rec in candidateRecs {
      #expect(rec.score.reasons.contains(.podcastAffinity))
    }
  }

  // MARK: - Arbitrary-list scoring

  @Test("recommendations(for:) scores every requested episode")
  func recommendationsForArbitraryList() async throws {
    let (_, signals) = try await createPodcastWithEpisodes(
      count: 3,
      podcastTitle: "Signal",
      ratings: [.loved, .liked, .liked]
    )
    try await embedEpisodes(signals)

    let (_, episodes) = try await createPodcastWithEpisodes(
      count: 4,
      podcastTitle: "Arbitrary"
    )
    try await embedEpisodes(episodes)

    let map = try await engine.recommendations(for: episodes)
    #expect(map.count == episodes.count)
    for episode in episodes {
      #expect(map[episode.id] != nil)
    }
  }

  @Test("recommendations(for:) returns empty when signal threshold isn't met")
  func recommendationsForArbitraryListBelowThreshold() async throws {
    let (_, signals) = try await createPodcastWithEpisodes(
      count: 2,
      podcastTitle: "Signal",
      ratings: [.loved, .liked]
    )
    try await embedEpisodes(signals)

    let (_, episodes) = try await createPodcastWithEpisodes(
      count: 3,
      podcastTitle: "Arbitrary"
    )
    try await embedEpisodes(episodes)

    let map = try await engine.recommendations(for: episodes)
    #expect(map.isEmpty)
  }

  @Test("recommendations(for:) scores rated and finished episodes the top API skips")
  func recommendationsForArbitraryListIncludesFilteredEpisodes() async throws {
    // Enough positive signals from a separate podcast to satisfy the threshold.
    let (_, signals) = try await createPodcastWithEpisodes(
      count: 3,
      podcastTitle: "Signal",
      ratings: [.loved, .liked, .liked]
    )
    try await embedEpisodes(signals)

    // Mixed bag: a disliked episode and a finished episode — both would be
    // excluded by `topRecommendations` via the candidate filter.
    let (_, filtered) = try await createPodcastWithEpisodes(
      count: 2,
      podcastTitle: "Filtered",
      ratings: [.disliked, nil],
      finished: [false, true]
    )
    try await embedEpisodes(filtered)

    let map = try await engine.recommendations(for: filtered)
    #expect(map.count == filtered.count)
    for episode in filtered {
      #expect(map[episode.id] != nil)
    }

    // Sanity-check: the same episodes are absent from the top API.
    let top = try await engine.topRecommendations()
    let topIDs = Set(top.map(\.episode.id))
    for episode in filtered {
      #expect(!topIDs.contains(episode.id))
    }
  }
}

// MARK: - Array Safe Subscript

extension Array {
  fileprivate subscript(safe index: Int) -> Element? {
    indices.contains(index) ? self[index] : nil
  }
}
