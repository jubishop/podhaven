// Copyright Justin Bishop, 2025

import Foundation
import Synchronization

final class ThreadSafe<Type: Sendable>: Sendable {
  private let mutex: Mutex<Type>

  init(_ value: Type) {
    mutex = Mutex<Type>(value)
  }

  func callAsFunction() -> Type {
    return mutex.withLock { $0 }
  }

  func callAsFunction(_ newValue: Type) {
    mutex.withLock { $0 = newValue }
  }

  func callAsFunction<Result>(_ operation: (inout Type) throws -> Result) rethrows -> Result {
    return try mutex.withLock { try operation(&$0) }
  }
}
