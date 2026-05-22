// Copyright Justin Bishop, 2026

import FactoryKit
import FactoryTesting
import Foundation
import Testing

@testable import PodHaven

@Suite("RecommendationEngine display anchor tests", .container)
class DisplayAnchorTests {
  @DynamicInjected(\.recommendationEngine) private var engine
  @DynamicInjected(\.userSettings) private var userSettings

  // Per-candidate surfaces (the Episode Detail score) rescale against the
  // engine's display anchor. With the Up Next list disabled the engine must
  // still score the pool to keep that anchor calibrated — otherwise detail
  // scores never reach 100%.
  @Test("display anchor stays calibrated when the Up Next list is disabled")
  func displayAnchorCalibratedWhenUpNextDisabled() async throws {
    let userSettings = self.userSettings
    userSettings.$maxRecommendedEpisodesInUpNext.new(0)
    // Pure podcast-affinity scoring gives every candidate a deterministic 0.8
    // raw score — above the 0.5 rescale floor and below 1.0.
    userSettings.$podcastAffinityWeight.new(1.0)

    let (lovedPodcast, signals) = try await RecommendationHelpers.createPodcastWithEpisodes(
      count: 3,
      podcastTitle: "Loved",
      ratings: [.loved, .loved, .loved]
    )
    try await RecommendationHelpers.embedEpisodes(signals)

    // Future pubDates so freshness short-circuits to a 1.0 multiplier,
    // leaving affinity (0.8) as the whole score.
    let candidates = try await RecommendationHelpers.addEpisodes(
      to: lovedPodcast,
      count: 2,
      pubDateOffset: { i in TimeInterval((i + 1) * 86400) }
    )
    try await RecommendationHelpers.embedEpisodes(candidates)

    let engine = self.engine
    engine.start()

    try await RecommendationHelpers.untilAdvancing(
      {
        let scores = try await engine.recommendations(for: candidates)
        let top = scores.values.map(\.value).max() ?? 0
        return top > 0.999
      },
      {
        let scores = try await engine.recommendations(for: candidates)
        let top = scores.values.map(\.value).max() ?? 0
        return """
          Expected the top candidate to rescale to 1.0 once the engine \
          calibrated its display anchor, but got \(top) — the anchor was \
          never updated because the Up Next list is disabled.
          """
      }
    )
  }
}
