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

  @Test(
    "non-rec sort stays alert-free when the background candidate observation fails"
  )
  func nonRecSortSuppressesRecommendationFailureAlert() async throws {
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
      // Wait for the failing candidate observation to be exercised so we
      // know handleRecommendationFailure ran. expectCalls polls until the
      // call lands.
      _ = try await Wait.until(
        priority: .userInitiated,
        {
          (try? fakeObservatory.expectCalls(
            methodName: "embeddedCandidateEpisodes",
            count: 1
          )) != nil
        },
        { "Expected candidate observation to be invoked once for non-rec sort." }
      )

      // Now poll for a short window that no alert ever shows up. A failing
      // background scoring path that pops a modal for users who aren't on
      // rec sort is the regression this test pins down.
      do {
        try await Wait.until(
          maxAttempts: 50,
          delay: .milliseconds(20),
          priority: .userInitiated,
          { @MainActor [self] in alert.config != nil },
          { "regression sentinel — see Issue.record below" }
        )
        Issue.record(
          """
          regression: candidate observation failure on a non-rec sort surfaced \
          a 'Couldn't compute recommendations' alert. Background scoring \
          failures must not interrupt users who aren't viewing the rec sort.
          """
        )
      } catch {
        // Expected timeout under the fixed implementation.
      }

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
            engine.start() was not called. A tick would kick a second \
            embeddedCandidateEpisodes fetch from recommendationContextObservationTask and \
            mask the view-model diff logic this test is meant to pin down.
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
}
