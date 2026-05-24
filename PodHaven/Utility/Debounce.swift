// Copyright Justin Bishop, 2026

import FactoryKit
import Foundation

final class Debounce: Sendable {
  private var sleeper: any Sleepable { Container.shared.sleeper() }
  private var taskPriority: @Sendable (TaskPriority?) -> TaskPriority? {
    Container.shared.taskPriority()
  }

  private let duration: Duration
  private let priority: TaskPriority?

  // Generation increments on every `callAsFunction` so the task body can
  // detect whether the stored entry still represents it before clearing.
  // Otherwise a racing call that replaces the stored task before the old
  // task's defer fires would have its replacement clobbered to nil.
  private struct State: Sendable {
    var task: Task<Void, Never>?
    var generation: Int = 0
  }
  private let state = ThreadSafe<State>(State())

  init(duration: Duration, priority: TaskPriority? = nil) {
    self.duration = duration
    self.priority = priority
  }

  // Convenience: uses the constructor-time `duration`.
  func callAsFunction(_ action: @escaping @Sendable () async -> Void) {
    callAsFunction(duration: duration, action)
  }

  // Per-call duration override. Use when the debounce window is computed
  // dynamically (e.g. `RecommendationEngine`'s adaptive window) so each call
  // can size its sleep against the latest observed work cost.
  func callAsFunction(duration: Duration, _ action: @escaping @Sendable () async -> Void) {
    let myGeneration: Int = state { state in
      state.task?.cancel()
      state.generation += 1
      return state.generation
    }
    let capturedPriority = priority
    let capturedSleeper = sleeper
    let capturedTaskPriority = taskPriority
    let newTask = Task(priority: capturedTaskPriority(capturedPriority)) { [weak self] in
      defer { self?.clearIfMatches(generation: myGeneration) }
      if duration > .zero {
        try? await capturedSleeper.sleep(for: duration)
      }
      guard !Task.isCancelled else { return }
      await action()
    }
    state { state in
      if state.generation == myGeneration {
        state.task = newTask
      } else {
        // A newer call landed between the cancel-and-bump above and this
        // install. Cancel the task we just created so it never runs `action`.
        newTask.cancel()
      }
    }
  }

  func cancel() {
    state { $0.task?.cancel() }
  }

  // True when a debounced action is armed (sleeping) or in-flight (running),
  // false once the most recent action's body has run to completion or bailed.
  // Use to detect whether work needs to be re-armed on a foreground transition
  // after `cancel()` killed an in-flight rebuild.
  var hasInFlightTask: Bool {
    state { $0.task != nil }
  }

  private func clearIfMatches(generation: Int) {
    state { state in
      if state.generation == generation { state.task = nil }
    }
  }
}
