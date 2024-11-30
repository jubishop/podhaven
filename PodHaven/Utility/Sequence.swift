// Copyright Justin Bishop, 2024

import Foundation

extension Array {
  public init(capacity: Int) {
    self.init()
    self.reserveCapacity(capacity)
  }
}

extension Dictionary {
  public init(capacity: Int) {
    self.init()
    self.reserveCapacity(capacity)
  }
}
