// Copyright Justin Bishop, 2026

import Observation

@testable import PodHaven

// Drives `viewModel.startCandidateObservation()` and
// `viewModel.startDisplayObservation()` in parallel loops, each restarting
// whenever its own observation key changes. SwiftUI's two `.task(id:)`
// blocks provide this behavior in production but are unavailable in unit
// tests; this helper replays the same semantics so tests can exercise both
// observation flows independently (sort toggles keep the candidate loop
// alive, filterText changes restart both, etc.).
@MainActor
func runObservationLoop(_ viewModel: EpisodesListViewModel) async {
  async let candidate: Void = runCandidateObservationLoop(viewModel)
  async let display: Void = runDisplayObservationLoop(viewModel)
  _ = await candidate
  _ = await display
}

// Wraps `runObservationLoop` so each test doesn't have to hand-roll the
// `Task.cancel() + viewModel.disappear()` teardown in both the success and
// catch arms — `defer` guarantees both fire.
@MainActor
func withRunningObservationLoop<T>(
  _ viewModel: EpisodesListViewModel,
  _ body: () async throws -> T
) async throws -> T {
  let task = Task { @MainActor in
    await runObservationLoop(viewModel)
  }
  defer {
    task.cancel()
    viewModel.disappear()
  }
  return try await body()
}

@MainActor
private func runCandidateObservationLoop(_ viewModel: EpisodesListViewModel) async {
  let (changes, continuation) = AsyncStream<Void>.makeStream()
  let watcher = CandidateKeyWatcher(viewModel: viewModel, continuation: continuation)
  _ = watcher

  defer { continuation.finish() }

  var iterator = changes.makeAsyncIterator()
  while !Task.isCancelled {
    let observationTask = Task { @MainActor in
      await viewModel.startCandidateObservation()
    }
    _ = await iterator.next()
    observationTask.cancel()
    _ = await observationTask.value
  }
}

@MainActor
private func runDisplayObservationLoop(_ viewModel: EpisodesListViewModel) async {
  let (changes, continuation) = AsyncStream<Void>.makeStream()
  let watcher = DisplayKeyWatcher(viewModel: viewModel, continuation: continuation)
  _ = watcher

  defer { continuation.finish() }

  var iterator = changes.makeAsyncIterator()
  while !Task.isCancelled {
    let observationTask = Task { @MainActor in
      await viewModel.startDisplayObservation()
    }
    _ = await iterator.next()
    observationTask.cancel()
    _ = await observationTask.value
  }
}

@MainActor
private final class CandidateKeyWatcher {
  private let viewModel: EpisodesListViewModel
  private let continuation: AsyncStream<Void>.Continuation

  init(viewModel: EpisodesListViewModel, continuation: AsyncStream<Void>.Continuation) {
    self.viewModel = viewModel
    self.continuation = continuation
    track()
  }

  private func track() {
    withObservationTracking {
      _ = viewModel.candidateObservationKey
    } onChange: { [weak self] in
      Task { @MainActor in
        guard let self else { return }
        self.continuation.yield()
        self.track()
      }
    }
  }
}

@MainActor
private final class DisplayKeyWatcher {
  private let viewModel: EpisodesListViewModel
  private let continuation: AsyncStream<Void>.Continuation

  init(viewModel: EpisodesListViewModel, continuation: AsyncStream<Void>.Continuation) {
    self.viewModel = viewModel
    self.continuation = continuation
    track()
  }

  private func track() {
    withObservationTracking {
      _ = viewModel.displayObservationKey
    } onChange: { [weak self] in
      Task { @MainActor in
        guard let self else { return }
        self.continuation.yield()
        self.track()
      }
    }
  }
}
