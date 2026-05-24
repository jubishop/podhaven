// Copyright Justin Bishop, 2026

import FactoryKit
import GRDB
import Testing

@testable import PodHaven

@Suite("of EpisodesListViewModel recommendation failure tests", .container)
@MainActor final class EpisodesListRecommendationFailureTests {
  @DynamicInjected(\.alert) private var alert
  @DynamicInjected(\.appDB) private var appDB
  @DynamicInjected(\.observatory) private var observatory

  @Test("rec-sort surfaces .failed (without an alert) when candidate observation throws")
  func candidateObservationFailureSurfacesFailedState() async throws {
    let fakeObservatory = try #require(observatory as? FakeObservatory)
    let dbReader = appDB.db
    fakeObservatory.embeddedCandidateEpisodesScript([
      {
        ValueObservation
          .tracking { _ -> [CandidateEpisode] in
            throw TestError.simulatedFailure
          }
          .values(in: dbReader)
      }
    ])

    let viewModel = EpisodesListViewModel(title: "RecFetchError")
    viewModel.currentSortMethod = .recommendationScore

    try await withRunningObservationLoop(viewModel) {
      try await Wait.until(
        priority: .userInitiated,
        { @MainActor in
          if case .failed = viewModel.loadingState { return true }
          return false
        },
        { @MainActor in
          """
          Expected .failed after candidate observation threw; got \
          \(viewModel.loadingState).
          """
        }
      )
      // The .failed UI alone conveys the failure — a modal alert on top of an
      // already-failed list is redundant. Pin that down so a future regression
      // re-adding alert(...) on the candidate-observation catch fails here.
      #expect(alert.config == nil)
    }
  }

  @Test(
    "rec-sort re-surfaces .failed on reappear when the candidate observation throws again"
  )
  func persistentCandidateObservationFailureSurfacesFailedAcrossReappear() async throws {
    let fakeObservatory = try #require(observatory as? FakeObservatory)
    let dbReader = appDB.db
    let scriptedFailure: @Sendable () -> AsyncValueObservation<[CandidateEpisode]> = {
      ValueObservation
        .tracking { _ -> [CandidateEpisode] in
          throw TestError.simulatedFailure
        }
        .values(in: dbReader)
    }
    fakeObservatory.embeddedCandidateEpisodesScript([scriptedFailure, scriptedFailure])

    let viewModel = EpisodesListViewModel(title: "RecPersistentFailureReappear")
    viewModel.currentSortMethod = .recommendationScore

    // First appear: the candidate observation throws and the failure UI surfaces.
    try await withRunningObservationLoop(viewModel) {
      try await Wait.until(
        priority: .userInitiated,
        { @MainActor in viewModel.loadingState == .failed },
        { @MainActor in
          "Expected .failed after first failure; got \(viewModel.loadingState)."
        }
      )
    }

    // Reappear: the candidate observation throws again. startDisplayObservation
    // resets loadingState to .loading on the way in; the second failure must
    // re-assert .failed so the UI doesn't strand on "Loading episodes…".
    //
    // The single-shot `Wait.until(loadingState == .failed)` would race-pass
    // against the prior block's leftover .failed before the second observation
    // even started, so first wait for the second `embeddedCandidateEpisodes`
    // call to confirm the new pass ran end-to-end, then assert .failed.
    @Sendable func embeddedCandidateCallCount() -> Int {
      fakeObservatory.callsByType()
        .values
        .flatMap { $0 }
        .filter { $0.methodName == "embeddedCandidateEpisodes" }
        .count
    }
    try await withRunningObservationLoop(viewModel) {
      try await Wait.until(
        priority: .userInitiated,
        { embeddedCandidateCallCount() >= 2 },
        { "Expected the reappear to re-enter the candidate observation." }
      )
      try await Wait.until(
        priority: .userInitiated,
        { @MainActor in viewModel.loadingState == .failed },
        { @MainActor in
          """
          Expected .failed after a second consecutive candidate-observation \
          failure on reappear; got \(viewModel.loadingState). A stale failure \
          marker is suppressing the loadingState write.
          """
        }
      )
    }
  }

  @Test("non-rec sort never reaches the candidate observation, even one scripted to fail")
  func nonRecSortNeverStartsFailingCandidateObservation() async throws {
    let fakeObservatory = try #require(observatory as? FakeObservatory)
    let dbReader = appDB.db
    fakeObservatory.embeddedCandidateEpisodesScript([
      {
        ValueObservation
          .tracking { _ -> [CandidateEpisode] in
            throw TestError.simulatedFailure
          }
          .values(in: dbReader)
      }
    ])

    let viewModel = EpisodesListViewModel(title: "NonRecFailureSilent")
    viewModel.currentSortMethod = .newestFirst

    try await withRunningObservationLoop(viewModel) {
      // The standard sort still settles on its own observation.
      try await Wait.until(
        priority: .userInitiated,
        { @MainActor in viewModel.loadingState == .loaded },
        { @MainActor in "Expected non-rec sort to settle, got \(viewModel.loadingState)." }
      )

      // Poll a window: a non-rec sort must never reach the candidate
      // observation, so the scripted failure never runs.
      do {
        try await Wait.until(
          maxAttempts: 50,
          delay: .milliseconds(20),
          priority: .userInitiated,
          { @MainActor in
            fakeObservatory.allCallsInOrder.contains {
              $0.methodName == "embeddedCandidateEpisodes"
            }
          },
          { "regression sentinel — see Issue.record below" }
        )
        Issue.record(
          """
          regression: a non-rec sort started the candidate observation. \
          Recommendation scoring must not run for users who aren't viewing \
          the rec sort.
          """
        )
      } catch {
        // Expected timeout under the fixed implementation.
      }

      try fakeObservatory.expectNoCall(methodName: "embeddedCandidateEpisodes")
    }
  }

  @Test("rec-sort doesn't loop refetching when candidate observation fails")
  func recommendationSortDoesNotRetryLoopOnPersistentCandidateObservationError() async throws {
    // Embed real candidates so the rec-sort observation emits a non-empty
    // row set; without embedded rows the diff check against the cleared
    // marker is trivially equal and the loop can't manifest.
    let embeddable = ScriptedEmbeddable { _ in [1, 0, 0] }
    let (_, episodes) = try await RecommendationHelpers.createPodcastWithEpisodes(
      count: 2,
      podcastTitle: "Loop",
      podcastDescription: "Loop",
      episodeDescriptions: ["Loop 0", "Loop 1"]
    )
    try await RecommendationHelpers.embedEpisodes(episodes, embeddable: embeddable)

    let fakeObservatory = try #require(observatory as? FakeObservatory)
    let dbReader = appDB.db
    fakeObservatory.embeddedCandidateEpisodesScript([
      {
        ValueObservation
          .tracking { _ -> [CandidateEpisode] in
            throw TestError.simulatedFailure
          }
          .values(in: dbReader)
      }
    ])

    // engine.start() is not called in this test, so $scoringRevision should
    // emit only its initial value of 0 (via Broadcast's on-subscribe yield)
    // and never tick again. The no-retry-loop assertion below times out on
    // the absence of a second embeddedCandidateEpisodes call — a spurious tick from
    // the engine would kick that second call and the assertion would still
    // pass (we'd silently lose coverage of the view model's diff logic).
    // This watcher records an Issue on any tick past the initial yield so a
    // future engine-side regression surfaces explicitly instead of as flake.
    let engine = Container.shared.recommendationEngine()
    let revisionTickCount = ThreadSafe<Int>(0)
    let revisionWatcher = Task(priority: .userInitiated) {
      for await _ in engine.$scoringRevision.stream() {
        let count = revisionTickCount {
          $0 += 1
          return $0
        }
        if count > 1 {
          Issue.record(
            """
            scoringRevision ticked during a no-retry-loop test that assumes \
            engine.start() was not called. A tick would kick a second scoring \
            pass from the coordinator's revision observer and mask the view-model \
            diff logic this test is meant to pin down.
            """
          )
        }
      }
    }
    defer { revisionWatcher.cancel() }

    let viewModel = EpisodesListViewModel(
      title: "RecLoopGuard",
      filter: Episode.candidate
    )
    viewModel.currentSortMethod = .recommendationScore

    try await withRunningObservationLoop(viewModel) {
      try await Wait.until(
        priority: .userInitiated,
        { @MainActor in
          if case .failed = viewModel.loadingState { return true }
          return false
        },
        { @MainActor in
          """
          Expected .failed after the first failed candidate fetch landed; got \
          \(viewModel.loadingState).
          """
        }
      )

      // A persistent candidate-source failure should not keep re-entering
      // the candidate observation. This poll detects any post-failure retry;
      // under the fixed implementation the count is pinned at 1.
      @Sendable func embeddedCandidateCallCount() -> Int {
        fakeObservatory.callsByType()
          .values
          .flatMap { $0 }
          .filter { $0.methodName == "embeddedCandidateEpisodes" }
          .count
      }

      do {
        try await Wait.until(
          maxAttempts: 50,
          delay: .milliseconds(20),
          priority: .userInitiated,
          { embeddedCandidateCallCount() >= 2 },
          { "regression sentinel — see Issue.record below" }
        )
        Issue.record(
          """
          regression: embeddedCandidateEpisodes observation was retried after the first failure \
          (count=\(embeddedCandidateCallCount())); persistent rec errors trigger a \
          refetch loop while the observed embedded row set stays stable.
          """
        )
      } catch {
        // Expected timeout under the fixed implementation.
      }

      _ = try fakeObservatory.expectCalls(methodName: "embeddedCandidateEpisodes", count: 1)
    }
  }

  @Test("rec-sort recovers on reappear after a transient candidate-observation failure")
  func transientCandidateObservationFailureDoesNotStickAcrossReappear() async throws {
    Container.shared.userSettings().$recommendationDeconeMode.new(.focused)

    let embeddable = ScriptedEmbeddable { text in
      if text.contains("Filler") { return [0, 0, 1] }
      if text.contains("Signal") { return [1, 0, 0] }
      if text.contains("Target") { return [0, 1, 0] }
      return [0, 0, 1]
    }

    let (_, fillers) = try await RecommendationHelpers.createPodcastWithEpisodes(
      count: 10,
      podcastTitle: "Filler",
      podcastDescription: "Filler",
      episodeDescriptions: Array(repeating: "Filler", count: 10),
      ratings: Array(repeating: .notInterested, count: 10)
    )
    try await RecommendationHelpers.embedEpisodes(fillers, embeddable: embeddable)

    let (_, signals) = try await RecommendationHelpers.createPodcastWithEpisodes(
      count: 3,
      podcastTitle: "Signal",
      podcastDescription: "Signal",
      episodeDescriptions: ["Signal", "Signal", "Signal"],
      ratings: [.loved, .liked, .liked]
    )
    try await RecommendationHelpers.embedEpisodes(signals, embeddable: embeddable)

    let (_, targets) = try await RecommendationHelpers.createPodcastWithEpisodes(
      count: 2,
      podcastTitle: "Target",
      podcastDescription: "Target",
      episodeDescriptions: ["Target 0", "Target 1"]
    )
    try await RecommendationHelpers.embedEpisodes(targets, embeddable: embeddable)

    _ = try await RecommendationHelpers.startAndWaitForScores(for: targets)
    // Quiesce engine rebuilds before the first appear so scoringRevision — half
    // the scoring key — holds steady across all three appears below.
    try await RecommendationScoringTestHelpers.settleRecommendationEngine()

    let targetIDs = Set(targets.map(\.id))
    let viewModel = EpisodesListViewModel(
      title: "RecTransientFailure",
      filter: Episode.candidate
    )
    viewModel.currentSortMethod = .recommendationScore

    // First appear: the candidate observation succeeds and the scoring pass
    // lands, so the coordinator caches the score map against the current
    // ScoredInputsKey.
    try await withRunningObservationLoop(viewModel) {
      try await Wait.until(
        priority: .userInitiated,
        { @MainActor in
          Set(viewModel.episodeList.filteredEntries.compactMap(\.episodeID)) == targetIDs
        },
        { @MainActor in
          """
          Expected the initial scoring pass to surface both targets under rec sort.
          Actual: \(Set(viewModel.episodeList.filteredEntries.compactMap(\.episodeID)))
          """
        }
      )
    }

    // Second appear: the candidate observation throws. handleRecommendationFailure
    // surfaces the .failed UI; the loadingState transition proves it ran past
    // the cancellation guard.
    let fakeObservatory = try #require(observatory as? FakeObservatory)
    let dbReader = appDB.db
    fakeObservatory.embeddedCandidateEpisodesScript([
      {
        ValueObservation
          .tracking { _ -> [CandidateEpisode] in
            throw TestError.simulatedFailure
          }
          .values(in: dbReader)
      }
    ])
    try await withRunningObservationLoop(viewModel) {
      try await Wait.until(
        priority: .userInitiated,
        { @MainActor in viewModel.loadingState == .failed },
        { @MainActor in
          """
          Expected the candidate-observation failure to surface .failed; got \
          \(viewModel.loadingState).
          """
        }
      )
    }

    // Third appear: the candidate observation recovers and emits the same
    // candidate set at the same scoringRevision as the first appear. The
    // coordinator's retained score is still valid for those unchanged inputs,
    // so the reappear recovers by re-applying it — clearing the stuck .failed
    // state — without recomputing. loadingState moving .failed -> .loaded is
    // the unambiguous proof the reappear's refresh ran.
    try await withRunningObservationLoop(viewModel) {
      try await Wait.until(
        priority: .userInitiated,
        { @MainActor in
          viewModel.loadingState == .loaded
            && Set(viewModel.episodeList.filteredEntries.compactMap(\.episodeID)) == targetIDs
        },
        { @MainActor in
          """
          Re-appearing after a transient candidate-observation failure left rec \
          sort stuck on .failed instead of recovering.
          loadingState: \(viewModel.loadingState)
          entries: \(Set(viewModel.episodeList.filteredEntries.compactMap(\.episodeID)))
          """
        }
      )
    }
  }
}
