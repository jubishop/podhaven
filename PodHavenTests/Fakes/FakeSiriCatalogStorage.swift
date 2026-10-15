// Copyright Justin Bishop, 2026

import Foundation

@testable import PodHaven

// Holds the first background catalog write to model slow storage under GRDB's
// synchronous writer queue. Main-thread writes pass through so a launch-thread
// publication fails the test instead of deadlocking it.
final class FakeSiriCatalogStorage: Sendable {
  let catalogWriteHeld = ThreadSafe(false)
  let completedCatalogWrites = ThreadSafe(0)
  let mainThreadCatalogWrites = ThreadSafe(0)
  private let released = ThreadSafe(false)
  private let gate = DispatchSemaphore(value: 0)

  func replace(_ data: Data, at url: URL) throws {
    if !data.isEmpty {
      if Thread.isMainThread {
        mainThreadCatalogWrites { $0 += 1 }
      } else if !catalogWriteHeld() {
        catalogWriteHeld(true)
        gate.wait()
      }
    }
    try data.write(to: url, options: .atomic)
    if !data.isEmpty { completedCatalogWrites { $0 += 1 } }
  }

  func release() {
    let first = released { released in
      defer { released = true }
      return !released
    }
    if first { gate.signal() }
  }
}
