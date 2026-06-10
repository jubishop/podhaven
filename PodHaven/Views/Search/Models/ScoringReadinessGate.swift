// Copyright Justin Bishop, 2026

import FactoryKit
import Foundation

// MARK: - ScoringReadinessGate

// Tracks whether the recommendation engine can score, off a single
// $scoringRevision subscription that serves both awaitReady() and the
// close → open transition callback.
@MainActor
final class ScoringReadinessGate {
  @DynamicInjected(\.recommendationEngine) private var recommendationEngine
  @DynamicInjected(\.taskPriority) private var taskPriority

  // `.unavailable` means the engine finished a rebuild with no scoring
  // context; the banner hides instead of loading forever while awaitReady()
  // keeps waiting for a later rebuild to produce one.
  enum State: Equatable {
    case unknown
    case ready
    case unavailable
  }

  // Reading registers SwiftUI observation through the Broadcast registrar.
  @Broadcasted var state: State = .unknown

  private var watcherTask: Task<Void, Never>?
  private var onTransitionToReady: (@MainActor () -> Void)?

  // Arms the lifetime watcher. Stays armed so any close → open transition
  // fires the callback, letting the owner re-queue work that finished while
  // scoring was cold.
  func ensureWatching(onTransitionToReady: @escaping @MainActor () -> Void) {
    if let watcherTask, !watcherTask.isCancelled { return }
    self.onTransitionToReady = onTransitionToReady
    let engine = recommendationEngine
    watcherTask = Task(priority: taskPriority(.utility)) { [weak self] in
      // The replayed bootstrap emit seeds `wasOpen` and the initial state
      // without firing the transition callback, so only genuine rebuild
      // emits count as transitions.
      var wasOpen: Bool?
      for await revision in engine.$scoringRevision.stream() {
        if Task.isCancelled { return }
        guard let self else { return }
        let isOpen = engine.hasScoringContext
        let transitionedToOpen = isOpen && wasOpen == false
        wasOpen = isOpen
        self.apply(revision: revision, isOpen: isOpen)
        if transitionedToOpen { self.onTransitionToReady?() }
      }
    }
  }

  // Returns once scoring is ready (or the surrounding task is cancelled).
  // `.unavailable` keeps waiting: returning early would let callers fetch and
  // embed for nothing, then re-do all of it when the engine later warms.
  func awaitReady() async {
    for await current in $state.stream() {
      if Task.isCancelled { return }
      if current == .ready { return }
    }
  }

  // A rebuild that yields no context downgrades `.ready` so surfaces reflect
  // the cooled engine. Picks scored while it was warm keep rendering — the
  // banner checks pick count before consulting this state.
  private func apply(revision: Int, isOpen: Bool) {
    if isOpen {
      $state.new(.ready)
    } else if revision > 0 {
      $state.new(.unavailable)
    }
  }
}
