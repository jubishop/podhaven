// Copyright Justin Bishop, 2025

import Foundation

actor ActorArray<T: Sendable & Equatable> {
  private var items: [T]

  init(items: [T] = []) {
    self.items = items
  }

  func append(_ item: T) { items.append(item) }
  func setItems(_ items: [T]) { self.items = items }
  func getItems() -> [T] { items }
  func reset() { items.removeAll() }
  func count() -> Int { items.count }
  func contains(_ item: T) -> Bool { items.contains(item) }

  func waitForContains(item: T) async throws {
    try await Wait.until(
      { await self.contains(item) },
      { "Expected to contain \(item)" }
    )
  }

  func waitForCount(_ expectedCount: Int) async throws {
    try await Wait.until(
      { await self.count() >= expectedCount },
      { "Expected count \(expectedCount), but got \(await self.count())" }
    )
  }

  func waitForEquals(_ expected: [T]) async throws {
    try await Wait.until(
      { await self.getItems() == expected },
      { "Expected array to equal \(expected), but got \(await self.getItems())" }
    )
  }
}
