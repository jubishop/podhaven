// Copyright Justin Bishop, 2025

import Foundation
import IdentifiedCollections

extension Array {
  public init(capacity: Int) {
    self.init()
    self.reserveCapacity(capacity)
  }

  subscript(safe index: Int) -> Element? {
    indices.contains(index) ? self[index] : nil
  }
}

extension IdentifiedArray {
  func chunked(size: Int) -> [[Element]] {
    guard size > 0, count > 0 else { return [] }

    return stride(from: 0, to: count, by: size)
      .map { startIndex in
        let endIndex = Swift.min(startIndex + size, count)
        return Array(self[startIndex..<endIndex])
      }
  }
}

extension Dictionary {
  public init(capacity: Int) {
    self.init()
    self.reserveCapacity(capacity)
  }
}
