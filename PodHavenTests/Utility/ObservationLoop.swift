// Copyright Justin Bishop, 2026

import Observation

@testable import PodHaven

// Drives `viewModel.startDisplayObservation()`, restarting it whenever the
// display observation key changes. SwiftUI's `.task(id:)` block provides this
// behavior in production but is unavailable in unit tests; this helper replays
// the same semantics so tests can exercise sort toggles and filterText changes.
@MainActor
func runObservationLoop(_ viewModel: EpisodesListViewModel) async {
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

// Wraps `runObservationLoop` so each test doesn't have to hand-roll the
// cancellation and joined teardown in both success and failure paths.
// Also runs the SmartList row
// observation (production's second `.task`) so write-through sort changes
// round-trip back into the view model.
@MainActor
func withRunningObservationLoop<T>(
  _ viewModel: EpisodesListViewModel,
  _ body: () async throws -> T
) async throws -> T {
  let rowTask = Task { @MainActor in
    await viewModel.observeSmartList()
  }
  let task = Task { @MainActor in
    await runObservationLoop(viewModel)
  }
  let result: Result<T, any Error>
  do {
    result = .success(try await body())
  } catch {
    result = .failure(error)
  }
  rowTask.cancel()
  task.cancel()
  viewModel.disappear()
  await rowTask.value
  await task.value
  return try result.get()
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
