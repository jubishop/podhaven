// Copyright Justin Bishop, 2026

import FactoryKit
import Foundation

struct Debounce: Sendable {
  typealias Action = @Sendable () async -> Void

  // What a trigger does to an action that's already running. Under
  // `finishThenRerun`, the action finishes and then the debounce re-arms once
  // for the latest trigger that arrived meanwhile.
  enum RunningActionPolicy: Sendable {
    case cancel
    case finishThenRerun
  }

  private var sleeper: any Sleepable { Container.shared.sleeper() }
  private var taskPriority: @Sendable (TaskPriority?) -> TaskPriority? {
    Container.shared.taskPriority()
  }

  private let duration: Duration
  private let priority: TaskPriority?
  private let runningActionPolicy: RunningActionPolicy

  private enum Phase: Sendable {
    case idle
    case sleeping(Task<Void, Never>)
    case running(Task<Void, Never>, rerun: Action?)

    var task: Task<Void, Never>? {
      switch self {
      case .idle: nil
      case .sleeping(let task), .running(let task, _): task
      }
    }
  }

  // `generation` lets a task detect whether it's still the stored entry
  // before changing the phase — without it, a racing call that replaces the
  // task before the prior defer fires would have its replacement clobbered.
  private struct State: Sendable {
    var phase = Phase.idle
    var generation = 0
  }
  private let state = ThreadSafe<State>(State())

  init(
    duration: Duration,
    priority: TaskPriority? = nil,
    runningActionPolicy: RunningActionPolicy = .cancel
  ) {
    self.duration = duration
    self.priority = priority
    self.runningActionPolicy = runningActionPolicy
  }

  func callAsFunction(_ action: @escaping Action) {
    let priority = taskPriority(self.priority)
    state { state in
      // A cancelled action is already on its way out, so arm afresh.
      if runningActionPolicy == .finishThenRerun,
        case .running(let task, _) = state.phase, !task.isCancelled
      {
        state.phase = .running(task, rerun: action)
        return
      }
      state.phase.task?.cancel()
      state = arming(action, priority: priority, after: state)
    }
  }

  @discardableResult
  func cancel() -> Bool {
    state { state in
      guard let task = state.phase.task else { return false }
      task.cancel()
      return true
    }
  }

  // Callers store the result in the same critical section that read `current`,
  // so a zero-duration task can't reach its own locked steps before its handle
  // is published.
  private func arming(
    _ action: @escaping Action,
    priority: TaskPriority?,
    after current: State
  ) -> State {
    let generation = current.generation + 1
    let sleeper = self.sleeper
    let task = Task(priority: priority) {
      defer {
        self.state { state in
          guard state.generation == generation else { return }
          if case .running(_, let rerun?) = state.phase, !Task.isCancelled {
            state = arming(rerun, priority: priority, after: state)
          } else {
            state.phase = .idle
          }
        }
      }
      if duration > .zero {
        try? await sleeper.sleep(for: duration)
      }
      let proceeds = self.state { state in
        guard state.generation == generation, !Task.isCancelled,
          case .sleeping(let task) = state.phase
        else { return false }
        state.phase = .running(task, rerun: nil)
        return true
      }
      guard proceeds else { return }
      await action()
    }
    return State(phase: .sleeping(task), generation: generation)
  }
}
