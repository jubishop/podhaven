// Copyright Justin Bishop, 2024

import Foundation

extension Array {
  public init(capacity: Int) {
    self.init()
    self.reserveCapacity(capacity)
  }

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
