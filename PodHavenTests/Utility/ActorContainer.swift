// Copyright Justin Bishop, 2025

import Foundation

actor ActorContainer<T: Sendable & Equatable> {
  private var item: T?

  init(item: T? = nil) {
    self.item = item
  }

  func set(_ item: T) { self.item = item }
  func get() -> T? { item }
  func reset() { item = nil }
  func hasItem() -> Bool { item != nil }
  func isEqual(to other: T) -> Bool { item == other }

  func waitForItem() async throws {
    try await Wait.until(
      { await self.hasItem() },
      { "Expected to have an item" }
    )
  }

  func waitForEqual(to expected: T) async throws {
    try await Wait.until(
      { await self.isEqual(to: expected) },
      { "Expected item to equal \(expected), but got \(String(describing: await self.get()))" }
    )
  }
}
