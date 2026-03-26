// Copyright Justin Bishop, 2026

import FactoryKit
import Foundation

final class Debounce: Sendable {
  private let duration: Duration
  private let priority: TaskPriority?
  private let task = ThreadSafe<Task<Void, Never>?>(nil)

  private var sleeper: any Sleepable { Container.shared.sleeper() }

  init(duration: Duration, priority: TaskPriority? = nil) {
    self.duration = duration
    self.priority = priority
  }

  func callAsFunction(_ action: @escaping @Sendable () async -> Void) {
    task { existing in
      existing?.cancel()
      existing = Task(priority: priority) {
        if duration > .zero {
          try? await sleeper.sleep(for: duration)
        }
        guard !Task.isCancelled else { return }
        await action()
      }
    }
  }

  func cancel() {
    task { $0?.cancel() }
  }
}
