// Copyright Justin Bishop, 2026

import FactoryKit
import FactoryTesting
import Foundation
import Testing

@testable import PodHaven

@Suite("RecommendationEngine candidate filtering tests", .container)
class CandidateFilteringTests {
  @DynamicInjected(\.recommendationEngine) private var engine
  @DynamicInjected(\.sharedState) private var sharedState

  @Test("excludes finished episodes from candidates")
  func excludesFinished() async throws {
    let (_, signalEpisodes) = try await RecommendationHelpers.createPodcastWithEpisodes(
      count: 3,
      podcastTitle: "Signal",
      ratings: [.loved, .liked, .liked]
    )
    try await RecommendationHelpers.embedEpisodes(signalEpisodes)

    let (_, candidates) = try await RecommendationHelpers.createPodcastWithEpisodes(
      count: 2,
      podcastTitle: "Candidates",
      finished: [true, false]
    )
    try await RecommendationHelpers.embedEpisodes(candidates)

    let recommendations = try await RecommendationHelpers.startAndWaitForRecs()
    let recommendedIDs = Set(recommendations.map(\.id))

    #expect(!recommendedIDs.contains(candidates[0].id))
  }

  @Test("excludes rated episodes from candidates")
  func excludesRated() async throws {
    let (_, signalEpisodes) = try await RecommendationHelpers.createPodcastWithEpisodes(
      count: 3,
      podcastTitle: "Signal",
      ratings: [.loved, .liked, .liked]
    )
    try await RecommendationHelpers.embedEpisodes(signalEpisodes)

    let (_, rated) = try await RecommendationHelpers.createPodcastWithEpisodes(
      count: 1,
      podcastTitle: "Rated Candidate",
      ratings: [.disliked]
    )
    try await RecommendationHelpers.embedEpisodes(rated)

    // Only candidate is rated, so the candidate pool is empty and recs
    // come back empty either way — no point waiting on the cache.
    engine.start()
    let recommendations = try await engine.topRecommendations()
    let recommendedIDs = Set(recommendations.map(\.id))
    #expect(!recommendedIDs.contains(rated[0].id))
  }

  @Test("excludes onDeck episode from candidates")
  func excludesOnDeck() async throws {
    let (_, signals) = try await RecommendationHelpers.createPodcastWithEpisodes(
      count: 3,
      podcastTitle: "Signal",
      ratings: [.loved, .liked, .liked]
    )
    try await RecommendationHelpers.embedEpisodes(signals)

    let (candidatePodcast, candidates) = try await RecommendationHelpers.createPodcastWithEpisodes(
      count: 3,
      podcastTitle: "Candidates"
    )
    try await RecommendationHelpers.embedEpisodes(candidates)

    let onDeckEpisode = try #require(candidates.first)
    sharedState.$onDeck.new(
      OnDeck(from: PodcastEpisode(podcast: candidatePodcast, episode: onDeckEpisode))
    )

    let recs = try await RecommendationHelpers.startAndWaitForRecs()
    let recommendedIDs = Set(recs.map(\.id))
    #expect(!recommendedIDs.contains(onDeckEpisode.id))
  }
}
