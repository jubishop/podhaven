// Copyright Justin Bishop, 2025

import Foundation
import Synchronization

final class ThreadSafe<Type: ~Copyable>: Sendable {
  private let mutex: Mutex<Type>

  init(_ initialValue: consuming sending Type) {
    mutex = Mutex<Type>(initialValue)
  }

  borrowing func callAsFunction() -> Type where Type: Copyable {
    mutex.withLock { $0 }
  }

  borrowing func callAsFunction(_ newValue: Type) where Type: Sendable & Copyable {
    mutex.withLock { $0 = newValue }
  }

  @discardableResult
  borrowing func callAsFunction<Result: ~Copyable>(
    _ operation: (inout sending Type) throws -> sending Result
  ) rethrows -> Result {
    try mutex.withLock(operation)
  }
}
