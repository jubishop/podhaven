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

  @Test("rec-sort surfaces .failed and an alert when candidate observation throws")
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
      try await Wait.until(
        priority: .userInitiated,
        { @MainActor [self] in alert.config != nil },
        { @MainActor [self] in
          "Expected failure alert to be presented; alert.config = \(String(describing: alert.config))"
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
      // observation (so the scripted failure never runs) and must never raise
      // a recommendation alert.
      do {
        try await Wait.until(
          maxAttempts: 50,
          delay: .milliseconds(20),
          priority: .userInitiated,
          { @MainActor [self] in
            fakeObservatory.allCallsInOrder.contains {
              $0.methodName == "embeddedCandidateEpisodes"
            } || alert.config != nil
          },
          { "regression sentinel — see Issue.record below" }
        )
        Issue.record(
          """
          regression: a non-rec sort started the candidate observation or \
          surfaced a 'Couldn't compute recommendations' alert. Recommendation \
          scoring must not run — let alone interrupt — users who aren't viewing \
          the rec sort.
          """
        )
      } catch {
        // Expected timeout under the fixed implementation.
      }

      try fakeObservatory.expectNoCall(methodName: "embeddedCandidateEpisodes")
      #expect(alert.config == nil)
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
            pass from observeScoringRevision and mask the view-model diff \
            logic this test is meant to pin down.
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
    // lands, so recommendationScoresState becomes .loaded with a completed
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
    // forces recommendationScoresState to .failed; the failure alert it raises
    // proves it ran past the cancellation guard.
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
        { @MainActor [self] in alert.config != nil },
        { @MainActor [self] in
          """
          Expected the candidate-observation failure to surface a failure alert.
          alert.config = \(String(describing: alert.config))
          """
        }
      )
    }

    // Third appear: the candidate observation recovers and emits the same
    // candidate set at the same scoringRevision as the first appear. The
    // failure above clobbered recommendationScoresState to .failed, so
    // observeCandidateSet's key-match check finds no .loaded state and must
    // fall through to a rescore — skipping it leaves rec sort stuck on the
    // failure state forever. A scoped
    // embeddings(for:) call is the unambiguous signal that the kick ran;
    // loadingState alone is racy because episodeList still holds the stale
    // rows the first appear surfaced.
    let fakeRecommendationRepo = try #require(
      Container.shared.recommendationRepo() as? FakeRecommendationRepo
    )
    fakeRecommendationRepo.clearAllCalls()
    try await withRunningObservationLoop(viewModel) {
      try await Wait.until(
        priority: .userInitiated,
        {
          await MainActor.run {
            RecommendationScoringTestHelpers.scopedEmbeddingsCallCount(
              matching: targetIDs
            ) >= 1
          }
        },
        { @MainActor in
          """
          Re-appearing after a transient candidate-observation failure left rec \
          sort stuck: observeCandidateSet skipped the rescore, so the candidate \
          set was never rescored and recommendationScoresState stayed .failed.
          embeddings(for:) calls for the candidate set: \
          \(RecommendationScoringTestHelpers.scopedEmbeddingsCallCount(matching: targetIDs))
          """
        }
      )
      // The rescore ran — confirm it cleared the stuck failure state.
      try await Wait.until(
        priority: .userInitiated,
        { @MainActor in
          viewModel.loadingState == .loaded
            && Set(viewModel.episodeList.filteredEntries.compactMap(\.episodeID)) == targetIDs
        },
        { @MainActor in
          """
          The post-failure rescore ran but rec sort did not recover to .loaded.
          loadingState: \(viewModel.loadingState)
          entries: \(Set(viewModel.episodeList.filteredEntries.compactMap(\.episodeID)))
          """
        }
      )
    }
  }
}
