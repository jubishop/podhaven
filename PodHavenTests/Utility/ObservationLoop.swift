// Copyright Justin Bishop, 2026

import Observation

@testable import PodHaven

// Drives `viewModel.startObservation()` in a loop, restarting whenever
// `viewModel.observationKey` changes. SwiftUI's `.task(id:)` machinery
// provides this behavior in production but is unavailable in unit tests;
// this helper replays the same semantics so tests can exercise observation
// flows that depend on key changes (e.g., recommendation score bumps).
@MainActor
func runObservationLoop(_ viewModel: EpisodesListViewModel) async {
  let (changes, continuation) = AsyncStream<Void>.makeStream()
  let watcher = ObservationKeyWatcher(viewModel: viewModel, continuation: continuation)
  _ = watcher

  defer { continuation.finish() }

  var iterator = changes.makeAsyncIterator()
  while !Task.isCancelled {
    let observationTask = Task { @MainActor in
      await viewModel.startObservation()
    }
    _ = await iterator.next()
    observationTask.cancel()
    _ = await observationTask.value
  }
}

@MainActor
private final class ObservationKeyWatcher {
  private let viewModel: EpisodesListViewModel
  private let continuation: AsyncStream<Void>.Continuation

  init(viewModel: EpisodesListViewModel, continuation: AsyncStream<Void>.Continuation) {
    self.viewModel = viewModel
    self.continuation = continuation
    track()
  }

  private func track() {
    withObservationTracking {
      _ = viewModel.observationKey
    } onChange: { [weak self] in
      Task { @MainActor in
        guard let self else { return }
        self.continuation.yield()
        self.track()
      }
    }
  }
}
