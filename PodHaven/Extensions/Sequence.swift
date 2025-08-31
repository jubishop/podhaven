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

extension Dictionary {
  public init(capacity: Int) {
    self.init()
    self.reserveCapacity(capacity)
  }
}

extension Set {
  public init(capacity: Int) {
    self.init()
    self.reserveCapacity(capacity)
  }
}
