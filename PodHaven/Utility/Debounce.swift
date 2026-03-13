// Copyright Justin Bishop, 2026

import FactoryKit
import Foundation

final class Debounce: Sendable {
  private let duration: Duration
  private let task = ThreadSafe<Task<Void, Never>?>(nil)

  private var sleeper: any Sleepable { Container.shared.sleeper() }

  init(duration: Duration) {
    self.duration = duration
  }

  func callAsFunction(_ action: @escaping @Sendable () async -> Void) {
    let duration = duration
    let sleeper = sleeper
    task { existing in
      existing?.cancel()
      existing = Task {
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
