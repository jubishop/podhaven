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

// MARK: - Collection Extensions

extension ActorContainer where T: Collection {
  func count() -> Int {
    item?.count ?? 0
  }

  func contains(_ element: T.Element) -> Bool where T.Element: Equatable {
    item?.contains(element) ?? false
  }

  func waitForContains(item element: T.Element) async throws where T.Element: Equatable & Sendable {
    try await Wait.until(
      { await self.contains(element) },
      { "Expected to contain \(element)" }
    )
  }

  func waitForCount(_ expectedCount: Int) async throws {
    try await Wait.until(
      { await self.count() >= expectedCount },
      { "Expected count \(expectedCount), but got \(await self.count())" }
    )
  }
}

// MARK: - RangeReplaceableCollection Extensions

extension ActorContainer where T: RangeReplaceableCollection {
  func append(_ element: T.Element) {
    var collection = item ?? T()
    collection.append(element)
    item = collection
  }
}
