// Copyright Justin Bishop, 2025

import Foundation
import IdentifiedCollections
import Synchronization

final class ThreadSafe<Type: ~Copyable>: Sendable {
  fileprivate let mutex: Mutex<Type>

  init(_ initialValue: consuming sending Type) {
    mutex = Mutex<Type>(initialValue)
  }
}

// MARK: - Core Operations

extension ThreadSafe where Type: Copyable {
  // Getter for copyable types
  borrowing func callAsFunction() -> Type {
    mutex.withLock { $0 }
  }
}

extension ThreadSafe where Type: Sendable & Copyable {
  // Setter for types that are both Sendable and Copyable
  @discardableResult
  borrowing func callAsFunction(_ newValue: Type) -> Type {
    mutex.withLock {
      $0 = newValue
      return newValue
    }
  }
}

extension ThreadSafe {
  // Closure-based mutation for all types
  @discardableResult
  borrowing func callAsFunction<Result: ~Copyable>(
    _ operation: (inout sending Type) throws -> sending Result
  ) rethrows -> Result {
    try mutex.withLock(operation)
  }
}

// MARK: - Subscript Support for Collections

extension ThreadSafe where Type: Collection, Type.Index: Sendable, Type.Element: Copyable {
  // Read-only subscript for collections (Array, Set, etc.)
  subscript(index: Type.Index) -> Type.Element {
    mutex.withLock { $0[index] }
  }
}

extension ThreadSafe
where Type: MutableCollection, Type.Index: Sendable, Type.Element: Sendable & Copyable {
  // Read-write subscript for mutable collections
  subscript(index: Type.Index) -> Type.Element {
    get {
      mutex.withLock { $0[index] }
    }
    set {
      mutex.withLock { $0[index] = newValue }
    }
  }
}

// MARK: - Subscript Support for Dictionaries

extension ThreadSafe {
  // Special subscript for Dictionary-like types
  subscript<Key, Value>(key: Key) -> Value?
  where Type == [Key: Value], Key: Sendable, Value: Copyable {
    mutex.withLock { $0[key] }
  }

  // Read-write subscript for Dictionary with Sendable values
  subscript<Key, Value>(key: Key) -> Value?
  where Type == [Key: Value], Key: Sendable, Value: Sendable & Copyable {
    get {
      mutex.withLock { $0[key] }
    }
    set {
      mutex.withLock { $0[key] = newValue }
    }
  }
}

// MARK: - Subscript Support for IdentifiedArray

extension ThreadSafe {
  // Read-only subscript for IdentifiedArray using [id:] syntax
  subscript<ID, Element>(id id: ID) -> Element?
  where Type == IdentifiedArray<ID, Element>, ID: Hashable & Sendable, Element: Copyable {
    mutex.withLock { $0[id: id] }
  }

  // Read-write subscript for IdentifiedArray with Sendable elements
  subscript<ID, Element>(id id: ID) -> Element?
  where Type == IdentifiedArray<ID, Element>, ID: Hashable & Sendable, Element: Sendable & Copyable
  {
    get {
      mutex.withLock { $0[id: id] }
    }
    set {
      mutex.withLock { $0[id: id] = newValue }
    }
  }
}
