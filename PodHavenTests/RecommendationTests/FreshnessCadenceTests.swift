// Copyright Justin Bishop, 2026

import FactoryKit
import FactoryTesting
import Foundation
import Testing

@testable import PodHaven

@Suite("RecommendationEngine freshness cadence tests", .container)
class FreshnessCadenceTests {
  @DynamicInjected(\.repo) private var repo

  @Test("evergreen cadence preserves old episode scores against the weekly default")
  func evergreenCadencePreservesOldEpisodeScore() async throws {
    // Same embedding + same podcast title across candidates so similarity and
    // affinity are identical; the only thing varying between the two
    // candidates is the freshness cadence on their podcast row. Evergreen
    // multiplier is always 1.0; weekly at 365d ≈ 0.029 (after the 10.5d
    // plateau + 10.5d half-life). Use the unfiltered scoring API since the
    // weekly candidate's gated score falls below the top API's confidence
    // floor.
    let embeddable = ScriptedEmbeddable { _ in [1, 0, 0] }

    let (_, signals) = try await RecommendationHelpers.createPodcastWithEpisodes(
      count: 3,
      podcastTitle: "Signal",
      ratings: [.loved, .liked, .liked]
    )
    try await RecommendationHelpers.embedEpisodes(signals, embeddable: embeddable)

    let oldOffset: (Int) -> TimeInterval = { _ in TimeInterval(-365 * 86400) }

    let (_, weeklyCandidates) = try await RecommendationHelpers.createPodcastWithEpisodes(
      count: 1,
      podcastTitle: "Weekly Default",
      pubDateOffset: oldOffset
    )
    try await RecommendationHelpers.embedEpisodes(weeklyCandidates, embeddable: embeddable)

    let (evergreenPodcast, evergreenCandidates) =
      try await RecommendationHelpers.createPodcastWithEpisodes(
        count: 1,
        podcastTitle: "Evergreen Cadence",
        pubDateOffset: oldOffset
      )
    try await RecommendationHelpers.embedEpisodes(evergreenCandidates, embeddable: embeddable)
    var evergreenSettings = PodcastSettings.defaults
    evergreenSettings.freshnessCadence = .evergreen
    _ = try await repo.updatePodcastSettings(evergreenPodcast.id, evergreenSettings)

    let scores = try await RecommendationHelpers.startAndWaitForScores(
      for: weeklyCandidates + evergreenCandidates
    )
    let weeklyEpisode = try #require(weeklyCandidates.first)
    let evergreenEpisode = try #require(evergreenCandidates.first)
    let weeklyScore = try #require(scores[weeklyEpisode.id])
    let evergreenScore = try #require(scores[evergreenEpisode.id])

    // Evergreen × 1.0 dominates weekly × ~0.029 by orders of magnitude.
    #expect(evergreenScore.value > weeklyScore.value * 10)
    // Evergreen never surfaces .recentlyPublished — the user has opted out
    // of freshness signal — and weekly at this age is below the threshold.
    #expect(!evergreenScore.reasons.contains(.recentlyPublished))
    #expect(!weeklyScore.reasons.contains(.recentlyPublished))
  }

  @Test("monthly cadence retains older episode scores better than weekly")
  func monthlyCadenceOutpacesWeekly() async throws {
    let embeddable = ScriptedEmbeddable { _ in [1, 0, 0] }

    let (_, signals) = try await RecommendationHelpers.createPodcastWithEpisodes(
      count: 3,
      podcastTitle: "Signal",
      ratings: [.loved, .liked, .liked]
    )
    try await RecommendationHelpers.embedEpisodes(signals, embeddable: embeddable)

    // 60 days old: weekly (10.5d plateau + 10.5d half-life) gives
    // 1/(1 + 49.5/10.5) ≈ 0.175; monthly (45d plateau + 45d half-life) gives
    // 1/(1 + 15/45) ≈ 0.75.
    let oldOffset: (Int) -> TimeInterval = { _ in TimeInterval(-60 * 86400) }

    let (_, weeklyCandidates) = try await RecommendationHelpers.createPodcastWithEpisodes(
      count: 1,
      podcastTitle: "Weekly",
      pubDateOffset: oldOffset
    )
    try await RecommendationHelpers.embedEpisodes(weeklyCandidates, embeddable: embeddable)

    let (monthlyPodcast, monthlyCandidates) =
      try await RecommendationHelpers.createPodcastWithEpisodes(
        count: 1,
        podcastTitle: "Monthly",
        pubDateOffset: oldOffset
      )
    try await RecommendationHelpers.embedEpisodes(monthlyCandidates, embeddable: embeddable)
    var monthlySettings = PodcastSettings.defaults
    monthlySettings.freshnessCadence = .monthly
    _ = try await repo.updatePodcastSettings(monthlyPodcast.id, monthlySettings)

    let scores = try await RecommendationHelpers.startAndWaitForScores(
      for: weeklyCandidates + monthlyCandidates
    )
    let weeklyEpisode = try #require(weeklyCandidates.first)
    let monthlyEpisode = try #require(monthlyCandidates.first)
    let weeklyScore = try #require(scores[weeklyEpisode.id])
    let monthlyScore = try #require(scores[monthlyEpisode.id])

    #expect(monthlyScore.value > weeklyScore.value)
  }

  @Test("plateau keeps within-cadence episodes at full freshness")
  func plateauPreservesWithinCadenceEpisodes() async throws {
    let embeddable = ScriptedEmbeddable { _ in [1, 0, 0] }

    let (_, signals) = try await RecommendationHelpers.createPodcastWithEpisodes(
      count: 3,
      podcastTitle: "Signal",
      ratings: [.loved, .liked, .liked]
    )
    try await RecommendationHelpers.embedEpisodes(signals, embeddable: embeddable)

    // 6 days old on a weekly podcast → still inside the plateau, so
    // multiplier = 1.0 and the score equals the same-base evergreen score
    // for the same age. Older test using a 365d offset confirms the curve
    // *does* decay past the plateau.
    let withinCadenceOffset: (Int) -> TimeInterval = { _ in TimeInterval(-6 * 86400) }

    let (_, weeklyCandidates) = try await RecommendationHelpers.createPodcastWithEpisodes(
      count: 1,
      podcastTitle: "Weekly Plateau",
      pubDateOffset: withinCadenceOffset
    )
    try await RecommendationHelpers.embedEpisodes(weeklyCandidates, embeddable: embeddable)

    let (evergreenPodcast, evergreenCandidates) =
      try await RecommendationHelpers.createPodcastWithEpisodes(
        count: 1,
        podcastTitle: "Evergreen Plateau",
        pubDateOffset: withinCadenceOffset
      )
    try await RecommendationHelpers.embedEpisodes(evergreenCandidates, embeddable: embeddable)
    var evergreenSettings = PodcastSettings.defaults
    evergreenSettings.freshnessCadence = .evergreen
    _ = try await repo.updatePodcastSettings(evergreenPodcast.id, evergreenSettings)

    let scores = try await RecommendationHelpers.startAndWaitForScores(
      for: weeklyCandidates + evergreenCandidates
    )
    let weeklyEpisode = try #require(weeklyCandidates.first)
    let evergreenEpisode = try #require(evergreenCandidates.first)
    let weeklyScore = try #require(scores[weeklyEpisode.id])
    let evergreenScore = try #require(scores[evergreenEpisode.id])

    #expect(weeklyScore.value == evergreenScore.value)
    #expect(weeklyScore.reasons.contains(.recentlyPublished))
  }

  @Test("recently-published reason fires for fresh non-evergreen episodes")
  func recentlyPublishedFiresForFreshEpisodes() async throws {
    let (_, signals) = try await RecommendationHelpers.createPodcastWithEpisodes(
      count: 3,
      podcastTitle: "Signal",
      ratings: [.loved, .liked, .liked]
    )
    try await RecommendationHelpers.embedEpisodes(signals)

    // 1 day old on a weekly cadence → inside the 10.5d plateau, so
    // `freshness.inPlateau` is true and `.recentlyPublished` fires.
    let (_, fresh) = try await RecommendationHelpers.createPodcastWithEpisodes(
      count: 1,
      podcastTitle: "Fresh",
      pubDateOffset: { _ in TimeInterval(-1 * 86400) }
    )
    try await RecommendationHelpers.embedEpisodes(fresh)

    let scores = try await RecommendationHelpers.startAndWaitForScores(for: fresh)
    let freshEpisode = try #require(fresh.first)
    let freshScore = try #require(scores[freshEpisode.id])
    #expect(freshScore.reasons.contains(.recentlyPublished))
  }

  @Test("recently-published reason is suppressed for evergreen podcasts even when fresh")
  func recentlyPublishedSuppressedForEvergreen() async throws {
    let (_, signals) = try await RecommendationHelpers.createPodcastWithEpisodes(
      count: 3,
      podcastTitle: "Signal",
      ratings: [.loved, .liked, .liked]
    )
    try await RecommendationHelpers.embedEpisodes(signals)

    // Freshly published episode but on an evergreen podcast — multiplier is
    // 1.0 so the score is fine, but the reason should not surface.
    let (evergreenPodcast, candidates) = try await RecommendationHelpers.createPodcastWithEpisodes(
      count: 1,
      podcastTitle: "Evergreen",
      pubDateOffset: { _ in TimeInterval(-1 * 86400) }
    )
    try await RecommendationHelpers.embedEpisodes(candidates)
    var evergreenSettings = PodcastSettings.defaults
    evergreenSettings.freshnessCadence = .evergreen
    _ = try await repo.updatePodcastSettings(evergreenPodcast.id, evergreenSettings)

    let scores = try await RecommendationHelpers.startAndWaitForScores(for: candidates)
    let candidate = try #require(candidates.first)
    let candidateScore = try #require(scores[candidate.id])
    #expect(!candidateScore.reasons.contains(.recentlyPublished))
  }
}
