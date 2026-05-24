// Copyright Justin Bishop, 2026

import FactoryKit
import Foundation

struct Debounce: Sendable {
  private var sleeper: any Sleepable { Container.shared.sleeper() }
  private var taskPriority: @Sendable (TaskPriority?) -> TaskPriority? {
    Container.shared.taskPriority()
  }

  private let durationStorage: ThreadSafe<Duration>
  private let priority: TaskPriority?

  // Settable so adaptive callers can keep the debounce's internal value in
  // sync with the duration they want sleeps to use. Reads are taken at the
  // top of `callAsFunction` so the value seen by a given call is the one
  // the caller just set.
  var duration: Duration {
    get { durationStorage() }
    nonmutating set { durationStorage(newValue) }
  }

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
    self.durationStorage = ThreadSafe(duration)
    self.priority = priority
  }

  func callAsFunction(_ action: @escaping @Sendable () async -> Void) {
    let duration = self.duration
    let state = self.state
    let sleeper = self.sleeper
    let taskPriority = self.taskPriority
    let priority = self.priority

    let myGeneration: Int = state { state in
      state.task?.cancel()
      state.generation += 1
      return state.generation
    }
    let newTask = Task(priority: taskPriority(priority)) {
      defer {
        state { state in
          if state.generation == myGeneration { state.task = nil }
        }
      }
      if duration > .zero {
        try? await sleeper.sleep(for: duration)
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
}
