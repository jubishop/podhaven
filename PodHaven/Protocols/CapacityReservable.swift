// Copyright Justin Bishop, 2025

import Foundation

protocol CapacityReservable {
  init()
  mutating func reserveCapacity(_ minimumCapacity: Int)
}

extension CapacityReservable {
  public init(capacity: Int) {
    self.init()
    self.reserveCapacity(capacity)
  }
}

extension Array: CapacityReservable {}
extension ContiguousArray: CapacityReservable {}
extension Data: CapacityReservable {}
extension Dictionary: CapacityReservable {}
extension Set: CapacityReservable {}
extension String: CapacityReservable {}
