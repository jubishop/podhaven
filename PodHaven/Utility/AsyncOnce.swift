// Copyright Justin Bishop, 2026

import Foundation

// Ensures async startup work runs once while concurrent callers await the same task.
final class AsyncOnce: Sendable {
  private let task = ThreadSafe<Task<Void, Never>?>(nil)

  func run(_ operation: @escaping @Sendable () async -> Void) async {
    let task: Task<Void, Never> = self.task { task in
      if let task { return task }

      let newTask = Task {
        await operation()
      }
      task = newTask
      return newTask
    }

    await task.value
  }
}
