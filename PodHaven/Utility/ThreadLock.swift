// Copyright Justin Bishop, 2025

import Foundation

struct ThreadLock {
  private let lock = ThreadSafe(false)

  var claimed: Bool { lock() }

  func claim() -> Bool {
    lock {
      if $0 { return false }
      $0 = true
      return true
    }
  }

  func release() {
    lock(false)
  }
}
