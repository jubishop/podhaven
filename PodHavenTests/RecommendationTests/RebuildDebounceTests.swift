// Copyright Justin Bishop, 2026

import FactoryKit
import FactoryTesting
import Foundation
import Testing

@testable import PodHaven

// During an embedding backfill, scoring-input changes keep retriggering the
// rebuild debounces. A trigger that cancelled a running rebuild would throw
// its finished work away each time, so a long rebuild could never publish.
@Suite("RecommendationEngine rebuild debounce tests", .container)
class RebuildDebounceTests {
  @DynamicInjected(\.recommendationEngine) private var engine
  @DynamicInjected(\.recommendationRepo) private var recommendationRepo
  @DynamicInjected(\.sharedState) private var sharedState
  @DynamicInjected(\.sleeper) private var sleeper
  @DynamicInjected(\.userSettings) private var userSettings

  private var fakeSleeper: FakeSleeper {
    sleeper as! FakeSleeper
  }

  private var fakeRecommendationRepo: FakeRecommendationRepo {
    recommendationRepo as! FakeRecommendationRepo
  }

  @Test("a cache-rebuild trigger during a running rebuild lets it publish, then reruns once")
  func cacheRebuildTriggerDuringRunningRebuildReruns() async throws {
    let engine = self.engine
    let fakeRepo = self.fakeRecommendationRepo
    let fakeSleeper = self.fakeSleeper

    try await createScorableLibrary()

    // Intercept the cache rebuild that the observation's first emission arms.
    fakeRepo.armScoringContextInputsGate()
    engine.start()
    try await RecommendationHelpers.untilAdvancing(
      { fakeRepo.isScoringContextInputsGateSuspended },
      { "Expected the cache rebuild to suspend on the gated allScoringContextInputs read." }
    )
    let revisionBeforeRelease = engine.scoringRevision

    // A decone-mode change retriggers the cache debounce. A trigger that
    // cancels the running rebuild arms a fresh sleep at once, and one that
    // lets it finish arms nothing until it does, so poll a bounded window to
    // let the trigger land before the release either way.
    let pendingSleeps = fakeSleeper.pendingCount()
    userSettings.$recommendationDeconeMode.new(.focused)
    do {
      try await Wait.until(
        maxAttempts: 50,
        delay: .milliseconds(20),
        { fakeSleeper.pendingCount() > pendingSleeps },
        { "" }
      )
    } catch TestError.waitUntilFailure {}

    fakeRepo.clearAllCalls()
    fakeRepo.releaseScoringContextInputsGate()

    // No time advances here, so only the running rebuild can publish.
    try await Wait.until(
      { engine.scoringRevision == revisionBeforeRelease + 1 },
      {
        """
        Expected the running cache rebuild to publish after the trigger, but \
        $scoringRevision stayed \(engine.scoringRevision): the trigger cancelled it.
        """
      }
    )

    try await RecommendationScoringTestHelpers.settleRecommendationEngine()
    let rerunCount = fakeRepo.allCallsInOrder
      .count { $0.methodName == "allScoringContextInputs" }
    #expect(rerunCount == 1, "Expected one rerun after the trigger, got \(rerunCount).")
    #expect(engine.scoringRevision == revisionBeforeRelease + 2)
  }

  @Test(
    "a recommendations-rebuild trigger during a running rebuild lets it publish, then reruns once"
  )
  func recommendationsRebuildTriggerDuringRunningRebuildReruns() async throws {
    let engine = self.engine
    let fakeRepo = self.fakeRecommendationRepo
    let sharedState = self.sharedState

    let candidateIDs = try await createScorableLibrary()

    // Intercept the first recommendations rebuild, so the pool stays empty
    // until it publishes.
    fakeRepo.armEmbeddingsGate(matching: candidateIDs)
    engine.start()
    try await RecommendationHelpers.untilAdvancing(
      { fakeRepo.isEmbeddingsGateSuspended },
      { "Expected the recommendations rebuild to suspend on the gated embeddings read." }
    )

    // An affinity change bumps $scoringRevision and then, without
    // suspending, retriggers the recommendations debounce.
    let revisionBeforeTrigger = engine.scoringRevision
    userSettings.$podcastAffinityWeight.new(0.5)
    try await Wait.until(
      { engine.scoringRevision != revisionBeforeTrigger },
      { "Expected the affinity change to bump $scoringRevision." }
    )

    fakeRepo.clearAllCalls()
    fakeRepo.releaseEmbeddingsGate()

    // No time advances here, so only the running rebuild can publish.
    try await Wait.until(
      { !sharedState.recommendedEpisodePool.isEmpty },
      {
        """
        Expected the running recommendations rebuild to publish after the \
        trigger, but the pool stayed empty: the trigger cancelled it.
        """
      }
    )

    try await RecommendationHelpers.untilAdvancing(
      { fakeRepo.allCallsInOrder.contains { $0.methodName == "allCandidateEpisodes" } },
      { "Expected the trigger to rerun the recommendations rebuild." }
    )
    await RecommendationScoringTestHelpers.drainRecommendationSleeper()
    let rerunCount = fakeRepo.allCallsInOrder
      .count { $0.methodName == "allCandidateEpisodes" }
    #expect(rerunCount == 1, "Expected one rerun after the trigger, got \(rerunCount).")
  }

  // MARK: - Helpers

  @discardableResult
  private func createScorableLibrary() async throws -> Set<Episode.ID> {
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
    return Set(candidates.map(\.id))
  }
}
