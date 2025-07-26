// Copyright Justin Bishop, 2025

import Foundation

actor ActorArray<T> {
  private var items: [T] = []
  func append(_ item: T) { items.append(item) }
  func getItems() -> [T] { items }
  func reset() { items.removeAll() }
  func count() -> Int { items.count }
  func contains(_ item: T) -> Bool where T: Equatable { items.contains(item) }
}
