// Copyright Justin Bishop, 2026

import FactoryKit
import FactoryTesting
import Foundation
import Testing

@testable import PodHaven

@Suite("RecommendationEngine slider transition tests", .container)
class SliderTransitionTests {
  @DynamicInjected(\.recommendationEngine) private var engine
  @DynamicInjected(\.sharedState) private var sharedState
  @DynamicInjected(\.userSettings) private var userSettings

  // The slider write path goes through the engine's settings observer
  // (`userSettings.$maxRecommendedEpisodesInUpNext.stream().dropFirst()`
  // in `startObservingScoringContext`), which calls
  // `scheduleRecommendationsRebuild`. The rebuild reads the limit at fire
  // time: 0 publishes `[]`, non-zero publishes a fresh top-N. This test
  // pins both branches and the round-trip back to non-zero so a future
  // refactor can't quietly break either.
  @Test("slider 5 → 0 publishes empty, 0 → 3 republishes non-empty")
  func sliderTransitionsRepublish() async throws {
    let (_, signals) = try await RecommendationHelpers.createPodcastWithEpisodes(
      count: 3,
      podcastTitle: "Signal",
      ratings: [.loved, .liked, .liked]
    )
    try await RecommendationHelpers.embedEpisodes(signals)

    let (_, candidates) = try await RecommendationHelpers.createPodcastWithEpisodes(
      count: 5,
      podcastTitle: "Candidates"
    )
    try await RecommendationHelpers.embedEpisodes(candidates)

    engine.start()
    let sharedState = self.sharedState
    let userSettings = self.userSettings

    // Initial publish at the default limit (5) lands non-empty.
    _ = try await RecommendationHelpers.waitAdvancing { () -> [RankedRecommendation]? in
      let recs = sharedState.topRecommendations
      return recs.isEmpty ? nil : recs
    }

    // Flip to 0 — engine's settings observer fires, debounced rebuild
    // publishes `[]`.
    userSettings.$maxRecommendedEpisodesInUpNext.new(0)
    _ = try await RecommendationHelpers.waitAdvancing { () -> Bool? in
      sharedState.topRecommendations.isEmpty ? true : nil
    }

    // Flip to 3 — settings observer fires again, debounced rebuild
    // publishes a fresh top-N (capped at 3).
    userSettings.$maxRecommendedEpisodesInUpNext.new(3)
    let republished = try await RecommendationHelpers.waitAdvancing {
      () -> [RankedRecommendation]? in
      let recs = sharedState.topRecommendations
      return recs.isEmpty ? nil : recs
    }
    #expect(republished.count <= 3)
  }
}
