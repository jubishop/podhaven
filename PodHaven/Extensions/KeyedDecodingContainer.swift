// Copyright Justin Bishop, 2025

import Foundation

extension KeyedDecodingContainer {
  func decodeOptionalURL(forKey key: Key) -> URL? {
    guard contains(key),
      let stringValue = try? decode(String.self, forKey: key),
      !stringValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    else { return nil }

    return URL(string: stringValue)
  }
}
