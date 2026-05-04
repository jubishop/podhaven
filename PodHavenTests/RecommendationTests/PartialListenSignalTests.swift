// Copyright Justin Bishop, 2026

import AVFoundation
import FactoryKit
import FactoryTesting
import Foundation
import Testing

@testable import PodHaven

@Suite("RecommendationEngine partial-listen signal tests", .container)
class PartialListenSignalTests {
  @DynamicInjected(\.recommendationEngine) private var engine
  @DynamicInjected(\.repo) private var repo
  @DynamicInjected(\.sharedState) private var sharedState

  @Test("partial-listen signals contribute alongside ratings")
  func partialSignalsContribute() async throws {
    let (_, ratedEpisodes) = try await RecommendationHelpers.createPodcastWithEpisodes(
      count: 2,
      podcastTitle: "Rated",
      ratings: [.loved, .liked]
    )
    try await RecommendationHelpers.embedEpisodes(ratedEpisodes)

    let (_, playedEpisodes) = try await RecommendationHelpers.createPodcastWithEpisodes(
      count: 1,
      podcastTitle: "Played"
    )
    try await RecommendationHelpers.embedEpisodes(playedEpisodes)
    let played = try #require(playedEpisodes.first)
    try await repo.updatePlayback(
      played.id,
      currentTime: CMTime.seconds(900),
      playedFrom: CMTime.seconds(0),
      now: Date()
    )

    let (_, candidates) = try await RecommendationHelpers.createPodcastWithEpisodes(
      count: 2,
      podcastTitle: "Candidates"
    )
    try await RecommendationHelpers.embedEpisodes(candidates)

    let recs = try await RecommendationHelpers.startAndWaitForRecs()
    #expect(!recs.isEmpty)
  }

  @Test("partial signals lift podcast affinity for the played show")
  func partialSignalsLiftAffinity() async throws {
    let (playedPodcast, ratedEpisodes) = try await RecommendationHelpers.createPodcastWithEpisodes(
      count: 2,
      podcastTitle: "BaselineRatings",
      ratings: [.loved, .liked]
    )
    try await RecommendationHelpers.embedEpisodes(ratedEpisodes)

    let played = try await RecommendationHelpers.addEpisodes(to: playedPodcast, count: 1)
    try await RecommendationHelpers.embedEpisodes(played)
    let playedID = try #require(played.first?.id)
    try await repo.updatePlayback(
      playedID,
      currentTime: CMTime.seconds(1700),
      playedFrom: CMTime.seconds(0),
      now: Date()
    )

    let candidates = try await RecommendationHelpers.addEpisodes(to: playedPodcast, count: 1)
    try await RecommendationHelpers.embedEpisodes(candidates)

    let recs = try await RecommendationHelpers.startAndWaitForRecs()
    let candidateRec = try #require(recs.first { $0.id == candidates[0].id })
    #expect(candidateRec.score.reasons.contains(.podcastAffinity))
  }

  @Test("onDeck transition rebuilds the cache against fresh partial signals")
  func onDeckTransitionRebuildsCache() async throws {
    let (_, ratedEpisodes) = try await RecommendationHelpers.createPodcastWithEpisodes(
      count: 2,
      podcastTitle: "Rated",
      ratings: [.loved, .liked]
    )
    try await RecommendationHelpers.embedEpisodes(ratedEpisodes)

    let (_, candidates) = try await RecommendationHelpers.createPodcastWithEpisodes(
      count: 1,
      podcastTitle: "Candidate"
    )
    try await RecommendationHelpers.embedEpisodes(candidates)

    // Start the engine before any partial exists — initial cache lacks
    // the third signal, so the rating-only count is below threshold.
    engine.start()

    let (_, played) = try await RecommendationHelpers.createPodcastWithEpisodes(
      count: 1,
      podcastTitle: "Played"
    )
    try await RecommendationHelpers.embedEpisodes(played)
    let playedEpisode = try #require(played.first)
    try await repo.updatePlayback(
      playedEpisode.id,
      currentTime: CMTime.seconds(1500),
      playedFrom: CMTime.seconds(0),
      now: Date()
    )

    // No GRDB observation fires for the bitmap write. An onDeck id
    // transition is what propagates the partial signal into the cache.
    let onDeckEpisode = try #require(try await repo.podcastEpisode(playedEpisode.id))
    sharedState.$onDeck.new(OnDeck(from: onDeckEpisode))
    sharedState.$onDeck.new(nil)

    let engine = self.engine
    let recs = try await RecommendationHelpers.waitAdvancing {
      let recs = try await engine.topRecommendations()
      return recs.isEmpty ? nil : recs
    }
    #expect(!recs.isEmpty)
  }

  @Test("a started-but-no-bitmap episode is NOT a signal (legacy / pre-v41)")
  func startedWithoutBitmapNotSignal() async throws {
    let (_, signals) = try await RecommendationHelpers.createPodcastWithEpisodes(
      count: 3,
      podcastTitle: "Signal",
      ratings: [.loved, .liked, .liked]
    )
    try await RecommendationHelpers.embedEpisodes(signals)

    let (_, started) = try await RecommendationHelpers.createPodcastWithEpisodes(
      count: 1,
      podcastTitle: "Legacy"
    )
    let legacyID = try #require(started.first?.id)
    try await repo.updateCurrentTime(legacyID, currentTime: CMTime.seconds(60))

    let partials = try await repo.allUnratedListenedEpisodes()
    #expect(partials.contains { $0.id == legacyID } == false)
  }
}
