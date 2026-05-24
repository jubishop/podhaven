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
  @DynamicInjected(\.recommendationRepo) private var recommendationRepo
  @DynamicInjected(\.sharedState) private var sharedState
  @DynamicInjected(\.sleeper) private var sleeper

  private var fakeSleeper: FakeSleeper {
    sleeper as! FakeSleeper
  }

  private var fakeRecommendationRepo: FakeRecommendationRepo {
    recommendationRepo as! FakeRecommendationRepo
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
    } catch TestError.waitUntilFailure {
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
    } catch TestError.waitUntilFailure {
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

  // A debounce armed while active can still wake after the app backgrounded
  // during the 400ms debounce window. The debounced closure must re-check the
  // gate; otherwise it runs the full rebuild while backgrounded.
  @Test("a rebuild armed before background and firing mid-debounce is short-circuited")
  func midDebounceBackgroundDefersUntilForeground() async throws {
    let engine = self.engine
    let fakeSleeper = self.fakeSleeper

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

    _ = try await RecommendationHelpers.startAndWaitForRecs()
    try await RecommendationScoringTestHelpers.settleRecommendationEngine()
    let revAfterStart = engine.scoringRevision

    // Trigger a rebuild while active and wait for its debounce sleep to be
    // parked on FakeSleeper. This proves the trigger reached the engine and
    // the debounce window is open, without firing the action.
    let (_, moreSignals) = try await RecommendationHelpers.createPodcastWithEpisodes(
      count: 3,
      podcastTitle: "More Signal",
      ratings: [.loved, .loved, .loved]
    )
    try await RecommendationHelpers.embedEpisodes(moreSignals)
    try await fakeSleeper.waitForSleepRequests(count: 1)

    // Background while the debounce is still sleeping.
    engine.handleScenePhaseChange(to: .background)

    // Regression sentinel: advance the debounce. Under the bug the closure
    // wakes and runs the full rebuild without re-checking the gate.
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
        regression: a rebuild armed while active still ran after the app \
        backgrounded mid-debounce ($scoringRevision \(revAfterStart) -> \
        \(engine.scoringRevision)). The debounce closure must re-check the \
        gate before running expensive work.
        """
      )
    } catch TestError.waitUntilFailure {
      // Expected timeout under the fix: the closure re-checked and returned.
    }

    // Foreground: the deferred rebuild runs as exactly one coalesced rescan.
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
    } catch TestError.waitUntilFailure {
      Issue.record(
        """
        Expected the deferred rebuild to run as one coalesced rescan on the \
        next foreground ($scoringRevision \(revAfterStart) -> \
        \(revAfterStart + 1)), but it is \(engine.scoringRevision).
        """
      )
    }

    for _ in 0..<20 {
      await fakeSleeper.advanceTime(by: .milliseconds(400))
      await Task.yield()
    }
    #expect(engine.scoringRevision == revAfterStart + 1)
  }

  // Transient `.inactive` (Control Center pull-down, banner, app switcher
  // peek) must not defer rescans — only true `.background` does.
  @Test("a rescan trigger fired while .inactive runs normally without deferral")
  func inactiveTriggerRunsNormally() async throws {
    let engine = self.engine
    let fakeSleeper = self.fakeSleeper

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

    _ = try await RecommendationHelpers.startAndWaitForRecs()
    try await RecommendationScoringTestHelpers.settleRecommendationEngine()
    let revAfterStart = engine.scoringRevision

    // Transition to .inactive (transient system event). Must not flip the
    // rescan gate to deferred.
    engine.handleScenePhaseChange(to: .inactive)

    // Fire a rescan trigger via a fresh rating signal while .inactive.
    let (_, moreSignals) = try await RecommendationHelpers.createPodcastWithEpisodes(
      count: 3,
      podcastTitle: "More Signal",
      ratings: [.loved, .loved, .loved]
    )
    try await RecommendationHelpers.embedEpisodes(moreSignals)

    // The rescan should run normally without needing a foreground transition.
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
    } catch TestError.waitUntilFailure {
      Issue.record(
        """
        Expected a rescan trigger fired during .inactive to run normally \
        ($scoringRevision \(revAfterStart) -> \(revAfterStart + 1)), but it \
        is \(engine.scoringRevision). Transient .inactive transitions must \
        not defer rescans — only .background.
        """
      )
    }
  }

  // The reporter's log (feedback `podhaven:7500094756`) shows two
  // `scheduleCacheRebuild()` calls 0.9 s apart producing two full
  // `topRecommendations` passes back-to-back — the static 400 ms debounce was
  // too short to coalesce triggers spaced just outside its window. Under the
  // adaptive debounce's 1 s floor (#324), two triggers spaced ~800 ms apart
  // must collapse to a single completed cache rebuild.
  //
  // Uses two `recommendationDeconeMode` flips as the rebuild trigger because
  // the user-settings observation is synchronous-ish (Broadcast yields
  // directly to the engine's `for await`) and fires deterministically per
  // flip, whereas GRDB `ValueObservation` can coalesce two near-simultaneous
  // DB writes into a single emission under load.
  @Test(
    "two cache-rebuild triggers spaced 800ms apart coalesce to a single rebuild"
  )
  func twoTriggersStraddlingCurrentDebounceCollapseUnderAdaptiveFloor() async throws {
    let fakeSleeper = self.fakeSleeper
    let fakeRepo = self.fakeRecommendationRepo

    let userSettings = Container.shared.userSettings()
    userSettings.$recommendationDeconeMode.new(.focused)

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

    _ = try await RecommendationHelpers.startAndWaitForRecs()
    try await RecommendationScoringTestHelpers.settleRecommendationEngine()

    fakeRepo.clearAllCalls()
    let pendingAtStart = fakeSleeper.pendingCount()

    // Trigger 1: flip decone mode. The `$recommendationDeconeMode` observation
    // fires `scheduleCacheRebuild`, which arms `cacheDebounce`.
    userSettings.$recommendationDeconeMode.new(.exploratory)
    try await fakeSleeper.waitForSleepRequests(count: pendingAtStart + 1)

    // Advance 800 ms — well past the legacy 400 ms debounce (which would have
    // fired and started a full pass) and well below the adaptive 1 s floor
    // (which must still be sleeping).
    await fakeSleeper.advanceTime(by: .milliseconds(800))
    for _ in 0..<5 { await Task.yield() }

    // Trigger 2: flip decone mode again, within the 1 s adaptive window.
    let pendingBeforeTrigger2 = fakeSleeper.pendingCount()
    userSettings.$recommendationDeconeMode.new(.focused)
    try await fakeSleeper.waitForSleepRequests(count: pendingBeforeTrigger2 + 1)

    // Drain everything so any debounce that was going to fire has fired and
    // any work it kicked off has completed.
    try await RecommendationScoringTestHelpers.settleRecommendationEngine()

    let cacheRebuildCount = fakeRepo.allCallsInOrder
      .filter { $0.methodName == "allScoringContextInputs" }
      .count

    #expect(
      cacheRebuildCount == 1,
      """
      Expected the two cache-rebuild triggers spaced 800 ms apart to coalesce \
      into a single `allScoringContextInputs` pass under the adaptive 1 s \
      debounce floor, but saw \(cacheRebuildCount) passes. The legacy 400 ms \
      debounce produces two passes because trigger 2 arrives after the first \
      pass has already started — exactly the overlap pattern that produced \
      the reporter's two `topRecommendations` passes within ~1 s.
      """
    )
  }

  // `cpu_resource_fatal-2026-05-22-084220.ips` shows the reporter's app killed
  // after a rebuild burned 48 s of background CPU at 99 %. The rebuild had
  // started ~80 ms before background and ran flat-out for 48 s until the kill.
  // `RescanGate` (#329) only defers *new* triggers; an already-running rebuild
  // must also be cancelled on background so it can't write its result after
  // the system has suspended the app. Under the fix, the cancelled pass must
  // not update `sharedState.topRecommendations` when the gated read releases.
  @Test(
    "backgrounding while a recommendations rebuild is in flight cancels it so it does not write its result"
  )
  func backgroundCancelsInFlightRecommendationsRebuild() async throws {
    let engine = self.engine
    let fakeRepo = self.fakeRecommendationRepo
    let sharedState = self.sharedState

    let embeddable = ScriptedEmbeddable { text in
      if text.contains("Signal") { return [1, 0, 0] }
      // Strong similarity to the signal centroid so every candidate scores
      // above the 0.1 minimum threshold and lands in the baseline top-recs.
      if text.contains("Candidate") { return [0.95, 0.05, 0] }
      return [0, 0, 1]
    }

    let (_, signals) = try await RecommendationHelpers.createPodcastWithEpisodes(
      count: 3,
      podcastTitle: "Signal",
      ratings: [.loved, .liked, .liked]
    )
    try await RecommendationHelpers.embedEpisodes(signals, embeddable: embeddable)
    let (_, candidates) = try await RecommendationHelpers.createPodcastWithEpisodes(
      count: 5,
      podcastTitle: "Candidate"
    )
    try await RecommendationHelpers.embedEpisodes(candidates, embeddable: embeddable)

    _ = try await RecommendationHelpers.startAndWaitForRecs()
    try await RecommendationScoringTestHelpers.settleRecommendationEngine()

    let baselineTopRecs = sharedState.topRecommendations
    try #require(baselineTopRecs.count == 5)

    let candidateIDs = Set(candidates.map(\.id))
    fakeRepo.clearAllCalls()
    fakeRepo.armEmbeddingsGate(matching: candidateIDs)

    // Trigger a recs-only rebuild by shrinking the limit. The maxRec
    // observation fires `scheduleRecommendationsRebuild` directly without
    // touching cache.
    Container.shared.userSettings().$maxRecommendedEpisodesInUpNext.new(1)

    // Drain the debounce so the action fires and suspends on the gate.
    try await RecommendationHelpers.untilAdvancing(
      priority: .userInitiated,
      { fakeRepo.isEmbeddingsGateSuspended },
      { "Expected the recommendations rebuild to suspend on the gated embeddings read." }
    )

    // Background while the pass is mid-flight on the gated embeddings call.
    engine.handleScenePhaseChange(to: .background)

    // Release the gate so the suspended task can resume. Under the fix the
    // task is cancelled at background, so the post-gate `try await
    // recommendationRepo.embeddings(...)` throws `CancellationError` before
    // `setTopRecommendations` runs. Under the bug the task is uncancelled,
    // embeddings returns, scoring runs to completion, and top recs get
    // overwritten while backgrounded.
    fakeRepo.releaseEmbeddingsGate()

    // Real-time wait at `.background` priority so the `.utility` rebuild task
    // is never starved. 500 ms is far more than the scoring math + apply path
    // needs on the cooperative pool.
    try await Task.sleep(for: .milliseconds(500))

    #expect(
      sharedState.topRecommendations == baselineTopRecs,
      """
      Expected the in-flight recommendations rebuild to be cancelled on \
      background and NOT to overwrite `topRecommendations`, but it changed: \
      baseline \(baselineTopRecs) -> \(sharedState.topRecommendations). \
      A rebuild that the system has already backgrounded must not finish \
      writing its result — that is the burn pattern from \
      `cpu_resource_fatal-2026-05-22-084220.ips`.
      """
    )
  }
}
