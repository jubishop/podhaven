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
  @DynamicInjected(\.embeddingService) private var embeddingService
  @DynamicInjected(\.recommendationEngine) private var engine
  @DynamicInjected(\.repo) private var repo

  // MARK: - Helpers

  private func createPodcastWithEpisodes(
    count: Int,
    podcastTitle: String = String.random(),
    podcastDescription: String = String.random(),
    episodeDescriptions: [String]? = nil,
    ratings: [EpisodeRating?]? = nil,
    finished: [Bool]? = nil
  ) async throws -> [Episode] {
    let unsavedPodcast = try Create.unsavedPodcast(
      title: podcastTitle,
      description: podcastDescription
    )

    var episodes: [UnsavedPodcastEpisode] = []
    for i in 0..<count {
      let rating = ratings?[safe: i] ?? nil
      let isFinished = finished?[safe: i] ?? false
      let description = episodeDescriptions?[safe: i] ?? "Episode \(i) description"

      let unsavedEpisode = try Create.unsavedEpisode(
        title: "Episode \(i) of \(podcastTitle)",
        pubDate: Date().addingTimeInterval(TimeInterval(-i * 86400)),
        duration: CMTime(seconds: 1800, preferredTimescale: 1),
        description: description,
        finishDate: isFinished ? Date() : nil,
        rating: rating,
        ratingDate: rating != nil ? Date() : nil
      )
      episodes.append(
        UnsavedPodcastEpisode(unsavedPodcast: unsavedPodcast, unsavedEpisode: unsavedEpisode)
      )
    }

    let podcastEpisodes = try await repo.upsertPodcastEpisodes(episodes)
    return podcastEpisodes.map(\.episode)
  }

  private func embedEpisodes(_ episodes: [Episode]) async throws {
    let embedding = FakeContextualEmbedding()
    try await embeddingService.ensureEmbeddings(
      for: episodes,
      embedding: embedding,
      checkCancellation: false
    )
  }

  // MARK: - Minimum Threshold

  @Test("returns empty when fewer than 3 signal episodes")
  func minimumThreshold() async throws {
    let episodes = try await createPodcastWithEpisodes(
      count: 2,
      ratings: [.loved, .liked]
    )
    try await embedEpisodes(episodes)

    let recommendations = try await engine.getRecommendations()
    #expect(recommendations.isEmpty)
  }

  // MARK: - Basic Recommendations

  @Test("returns recommendations when threshold is met")
  func basicRecommendations() async throws {
    // Create rated episodes (signal)
    let signalEpisodes = try await createPodcastWithEpisodes(
      count: 3,
      podcastTitle: "Signal Podcast",
      ratings: [.loved, .liked, .liked]
    )
    try await embedEpisodes(signalEpisodes)

    // Create candidate episodes (unrated, unfinished, unqueued)
    let candidateEpisodes = try await createPodcastWithEpisodes(
      count: 3,
      podcastTitle: "Candidate Podcast"
    )
    try await embedEpisodes(candidateEpisodes)

    let recommendations = try await engine.getRecommendations()
    #expect(!recommendations.isEmpty)
    #expect(recommendations.count <= 10)

    // Verify deterministic ordering (scores should be descending)
    for i in 0..<(recommendations.count - 1) {
      #expect(recommendations[i].score >= recommendations[i + 1].score)
    }
  }

  // MARK: - Candidate Filtering

  @Test("excludes finished episodes from candidates")
  func excludesFinished() async throws {
    let signalEpisodes = try await createPodcastWithEpisodes(
      count: 3,
      podcastTitle: "Signal",
      ratings: [.loved, .liked, .liked]
    )
    try await embedEpisodes(signalEpisodes)

    let candidates = try await createPodcastWithEpisodes(
      count: 2,
      podcastTitle: "Candidates",
      finished: [true, false]
    )
    try await embedEpisodes(candidates)

    let recommendations = try await engine.getRecommendations()
    let recommendedIDs = Set(recommendations.map(\.episode.id))

    #expect(!recommendedIDs.contains(candidates[0].id))
  }

  @Test("excludes rated episodes from candidates")
  func excludesRated() async throws {
    let signalEpisodes = try await createPodcastWithEpisodes(
      count: 3,
      podcastTitle: "Signal",
      ratings: [.loved, .liked, .liked]
    )
    try await embedEpisodes(signalEpisodes)

    let rated = try await createPodcastWithEpisodes(
      count: 1,
      podcastTitle: "Rated Candidate",
      ratings: [.disliked]
    )
    try await embedEpisodes(rated)

    let recommendations = try await engine.getRecommendations()
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

    let candidates = try await createPodcastWithEpisodes(
      count: 2,
      podcastTitle: "Candidates"
    )
    try await embedEpisodes(candidates)

    // Should return empty since there's no positive centroid
    let recommendations = try await engine.getRecommendations()
    #expect(recommendations.isEmpty)
  }

  // MARK: - Reasons

  @Test("recommendations include reasons")
  func recommendationsHaveReasons() async throws {
    let signalEpisodes = try await createPodcastWithEpisodes(
      count: 3,
      podcastTitle: "Signal",
      ratings: [.loved, .liked, .liked]
    )
    try await embedEpisodes(signalEpisodes)

    let candidates = try await createPodcastWithEpisodes(
      count: 2,
      podcastTitle: "Candidates"
    )
    try await embedEpisodes(candidates)

    let recommendations = try await engine.getRecommendations()
    for rec in recommendations {
      #expect(!rec.reasons.isEmpty)
    }
  }
}

// MARK: - Array Safe Subscript

extension Array {
  fileprivate subscript(safe index: Int) -> Element? {
    indices.contains(index) ? self[index] : nil
  }
}
