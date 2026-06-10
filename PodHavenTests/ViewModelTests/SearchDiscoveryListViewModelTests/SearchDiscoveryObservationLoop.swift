// Copyright Justin Bishop, 2026

import Observation

@testable import PodHaven

// Drives `viewModel.observeSavedEpisodes()`, restarting it whenever the
// saved-observation task key changes. SwiftUI's `.task(id:)` block provides this
// behavior in production but is unavailable in unit tests; this helper replays
// the same semantics so tests can exercise pick-set and onDeck changes.
@MainActor
func runDiscoveryObservationLoop(_ viewModel: SearchDiscoveryListViewModel) async {
  let (changes, continuation) = AsyncStream<Void>.makeStream()
  let watcher = SavedObservationTaskKeyWatcher(
    viewModel: viewModel,
    continuation: continuation
  )

  // Nothing else holds the watcher strongly; without this, ARC could release
  // it after its last use and silently stop replaying key-change restarts.
  defer {
    withExtendedLifetime(watcher) {}
    continuation.finish()
  }

  var iterator = changes.makeAsyncIterator()
  while !Task.isCancelled {
    let observationTask = Task { @MainActor in
      await viewModel.observeSavedEpisodes()
    }
    _ = await iterator.next()
    observationTask.cancel()
    _ = await observationTask.value
  }
}

// Wraps `runDiscoveryObservationLoop` so each test doesn't have to hand-roll
// the `Task.cancel()` teardown in both the success and catch arms — `defer`
// guarantees both fire.
@MainActor
func withRunningDiscoveryObservationLoop<T>(
  _ viewModel: SearchDiscoveryListViewModel,
  _ body: () async throws -> T
) async throws -> T {
  let task = Task { @MainActor in
    await runDiscoveryObservationLoop(viewModel)
  }
  defer { task.cancel() }
  return try await body()
}

@MainActor
private final class SavedObservationTaskKeyWatcher {
  private let viewModel: SearchDiscoveryListViewModel
  private let continuation: AsyncStream<Void>.Continuation
  private var currentKey: SearchDiscoveryListViewModel.SavedObservationTaskKey

  init(viewModel: SearchDiscoveryListViewModel, continuation: AsyncStream<Void>.Continuation) {
    self.viewModel = viewModel
    self.continuation = continuation
    currentKey = viewModel.savedObservationTaskKey
    track()
  }

  private func track() {
    withObservationTracking {
      _ = viewModel.savedObservationTaskKey
    } onChange: { [weak self] in
      Task { @MainActor in
        guard let self else { return }
        let nextKey = self.viewModel.savedObservationTaskKey
        let changed = nextKey != self.currentKey
        self.currentKey = nextKey
        if changed { self.continuation.yield() }
        self.track()
      }
    }
  }
}
