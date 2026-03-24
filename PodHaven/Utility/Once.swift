// Copyright Justin Bishop, 2026

import FactoryKit
import Foundation

extension Container {
  fileprivate var claimedOnceIDs: Factory<ThreadSafe<Set<String>>> {
    Factory(self) { ThreadSafe<Set<String>>([]) }.scope(.cached)
  }
}

// Ensures one-shot synchronous setup runs once, either per owning instance
// or per explicit string identifier.
final class Once: Sendable {
  private static var claimedIDs: ThreadSafe<Set<String>> { Container.shared.claimedOnceIDs() }

  private let hasRun = ThreadSafe(false)

  @discardableResult
  func claim() -> Bool {
    hasRun { hasRun in
      guard hasRun == false else { return false }
      hasRun = true
      return true
    }
  }

  func run(_ operation: () -> Void) {
    guard claim() else { return }

    operation()
  }

  @discardableResult
  static func claim(_ id: String) -> Bool {
    claimedIDs { claimedIDs in
      guard claimedIDs.contains(id) == false else { return false }
      claimedIDs.insert(id)
      return true
    }
  }

  static func run(_ id: String, _ operation: () -> Void) {
    guard claim(id) else { return }

    operation()
  }
}
