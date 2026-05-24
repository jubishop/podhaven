// Copyright Justin Bishop, 2026

import FactoryKit
import Foundation

struct Debounce: Sendable {
  private var sleeper: any Sleepable { Container.shared.sleeper() }
  private var taskPriority: @Sendable (TaskPriority?) -> TaskPriority? {
    Container.shared.taskPriority()
  }

  private let duration: Duration
  private let priority: TaskPriority?

  // `generation` lets a task's defer detect whether it's still the stored
  // entry before clearing — without it, a racing call that replaces the
  // task before the prior defer fires would have its replacement clobbered.
  private struct State: Sendable {
    var task: Task<Void, Never>?
    var generation: Int = 0
  }
  private let state = ThreadSafe<State>(State())

  init(duration: Duration, priority: TaskPriority? = nil) {
    self.duration = duration
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
        newTask.cancel()
      }
    }
  }

  func cancel() {
    state { $0.task?.cancel() }
  }

  var hasInFlightTask: Bool {
    state { $0.task != nil }
  }
}
