// Copyright Justin Bishop, 2026

import FactoryKit
import Foundation
import Logging

struct AdaptiveDebounce: Sendable {
  let capacity: Int
  let minimumDuration: Duration
  let maximumDuration: Duration
  let safetyMultiplier: Double

  @DynamicInjected(\.continuousClockNow) private var continuousClockNow
  @DynamicInjected(\.sleeper) private var sleeper
  @DynamicInjected(\.taskPriority) private var taskPriority

  private let priority: TaskPriority?
  private let persistedWindow: PersistedThreadSafe<[Duration]>
  private let log: Logger

  // `generation` lets a task's defer detect whether it's still the stored
  // entry before clearing — without it, a racing call that replaces the
  // task before the prior defer fires would have its replacement clobbered.
  private struct State: Sendable {
    var task: Task<Void, Never>?
    var generation: Int = 0
  }
  private let state = ThreadSafe<State>(State())

  init(
    name: String,
    priority: TaskPriority? = nil,
    capacity: Int = 5,
    minimumDuration: Duration = .seconds(1),
    maximumDuration: Duration = .seconds(120),
    safetyMultiplier: Double = 2.0
  ) {
    self.priority = priority
    self.capacity = capacity
    self.minimumDuration = minimumDuration
    self.maximumDuration = maximumDuration
    self.safetyMultiplier = safetyMultiplier
    self.persistedWindow = PersistedThreadSafe(
      wrappedValue: [Duration](),
      "adaptiveDebounce.\(name).passDurations"
    )
    self.log = Log.as("AdaptiveDebounce.\(name)")
  }

  var passDurations: [Duration] { persistedWindow.wrappedValue }
  var hasInFlightTask: Bool { state { $0.task != nil } }

  func cancel() {
    state { $0.task?.cancel() }
  }

  // Bool action: records only when the closure returns `true`. Use when the
  // action can fail or short-circuit (guard, catch, return false) and only
  // successful passes should adapt the window.
  func callAsFunction(_ action: @escaping @Sendable () async -> Bool) {
    schedule { [self] in
      let start = continuousClockNow()
      let succeeded = await action()
      if succeeded {
        recordCompletedPass(continuousClockNow() - start)
      }
    }
  }

  // Void action: always records on completion.
  func callAsFunction(_ action: @escaping @Sendable () async -> Void) {
    schedule { [self] in
      let start = continuousClockNow()
      await action()
      recordCompletedPass(continuousClockNow() - start)
    }
  }

  private func schedule(_ work: @escaping @Sendable () async -> Void) {
    let duration = computeDebounce()
    let sleeper = self.sleeper
    let taskPriority = self.taskPriority
    let priority = self.priority
    let state = self.state

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
      await work()
    }
    state { state in
      if state.generation == myGeneration {
        state.task = newTask
      } else {
        newTask.cancel()
      }
    }
  }

  // Single-flight by construction: the schedule() task lifecycle cancels any
  // prior in-flight pass before arming the next, so there is never more than
  // one writer at a time. The read-modify-write below is therefore safe.
  private func recordCompletedPass(_ duration: Duration) {
    let scaled = duration * safetyMultiplier
    if scaled > maximumDuration {
      log.warning(
        "Hit \(maximumDuration) cap; pass × \(safetyMultiplier) was \(scaled)."
      )
    }
    var updated = [duration] + persistedWindow.wrappedValue
    if updated.count > capacity {
      updated.removeLast(updated.count - capacity)
    }
    persistedWindow.wrappedValue = updated
  }

  private func computeDebounce() -> Duration {
    guard let worst = persistedWindow.wrappedValue.max() else {
      return minimumDuration
    }
    let scaled = worst * safetyMultiplier
    if scaled > maximumDuration { return maximumDuration }
    if scaled < minimumDuration { return minimumDuration }
    return scaled
  }
}
