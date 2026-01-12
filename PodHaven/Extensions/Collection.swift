// Copyright Justin Bishop, 2025

import Foundation

extension Collection {
  func asyncMap<T>(_ transform: (Element) async throws -> T) async rethrows -> [T] {
    var results = [T](capacity: count)
    for element in self {
      try await results.append(transform(element))
    }
    return results
  }
}
