// Copyright Justin Bishop, 2026

import FactoryKit
import FactoryTesting
import Foundation
import SwiftUI
import Testing

@testable import PodHaven

@Suite("RecommendationEngine background rescan suppression tests", .container)
class BackgroundRescanSuppressionTests {
  @DynamicInjected(\.recommendationEngine) private var engine
  @DynamicInjected(\.sleeper) private var sleeper

  private var fakeSleeper: FakeSleeper {
    sleeper as! FakeSleeper
  }

  // A backgrounded audio session has a tight CPU/memory budget, so a rescan
  // trigger that fires while backgrounded must not start a full-library scan.
  // Deferred triggers coalesce into exactly one rescan on the next foreground.
  @Test("a rescan trigger fired while backgrounded defers until the next foreground")
  func backgroundedTriggerDefersUntilForeground() async throws {
    let engine = self.engine
    let fakeSleeper = self.fakeSleeper

    // A signal + candidate library so the engine builds a non-empty cache.
    let (_, signals) = try await RecommendationHelpers.createPodcastWithEpisodes(
      count: 3,
      podcastTitle: "Signal",
      ratings: [.loved, .liked, .liked]
    )
    try await RecommendationHelpers.embedEpisodes(signals)
    let (_, candidates) = try await RecommendationHelpers.createPodcastWithEpisodes(
      count: 3,
      podcastTitle: "Candidate"
    )
    try await RecommendationHelpers.embedEpisodes(candidates)

    // Start the engine and quiesce every bootstrap rebuild.
    _ = try await RecommendationHelpers.startAndWaitForRecs()
    try await RecommendationScoringTestHelpers.settleRecommendationEngine()
    let revAfterStart = engine.scoringRevision

    // Background, then fire a rescan trigger via fresh rating signals.
    engine.handleScenePhaseChange(to: .background)
    let (_, moreSignals) = try await RecommendationHelpers.createPodcastWithEpisodes(
      count: 3,
      podcastTitle: "More Signal",
      ratings: [.loved, .loved, .loved]
    )
    try await RecommendationHelpers.embedEpisodes(moreSignals)

    // Regression sentinel: poll a window, advancing the debounce each round,
    // for a rescan to run while backgrounded. The real-time delay lets the
    // trigger's DB observation reach the engine; advancing fires any rescan it
    // armed. Under the fix the trigger is deferred and the poll times out.
    do {
      try await Wait.until(
        maxAttempts: 100,
        delay: .milliseconds(20),
        {
          await fakeSleeper.advanceTime(by: .milliseconds(400))
          return engine.scoringRevision != revAfterStart
        },
        { "regression sentinel — see Issue.record below" }
      )
      Issue.record(
        """
        regression: a full-library rescan ran while the app was backgrounded \
        ($scoringRevision \(revAfterStart) -> \(engine.scoringRevision)). A \
        backgrounded audio session must defer rescans to the next foreground.
        """
      )
    } catch {
      // Expected timeout under the fix: the trigger was deferred.
    }

    // Foreground: the deferred trigger runs as exactly one coalesced rescan.
    engine.handleScenePhaseChange(to: .active)
    do {
      try await Wait.until(
        maxAttempts: 100,
        delay: .milliseconds(20),
        {
          await fakeSleeper.advanceTime(by: .milliseconds(400))
          return engine.scoringRevision == revAfterStart + 1
        },
        { "" }
      )
    } catch {
      Issue.record(
        """
        Expected the deferred trigger to run as one coalesced rescan on the \
        next foreground ($scoringRevision \(revAfterStart) -> \
        \(revAfterStart + 1)), but it is \(engine.scoringRevision).
        """
      )
    }

    // The coalesced rescan settles without a second pass.
    for _ in 0..<20 {
      await fakeSleeper.advanceTime(by: .milliseconds(400))
      await Task.yield()
    }
    #expect(engine.scoringRevision == revAfterStart + 1)
  }
}
