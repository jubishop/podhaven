// Copyright Justin Bishop, 2025

import Foundation

func valuesEqual(_ lhs: Any?, _ rhs: Any?) -> Bool {
  switch (lhs, rhs) {
  case (nil, nil):
    return true
  case (nil, _), (_, nil):
    return false
  case (let l as any Equatable, let r as any Equatable):
    return l.isEqual(to: r)
  default:
    return false
  }
}

extension Equatable {
  func isEqual(to other: any Equatable) -> Bool {
    guard let other = other as? Self else {
      return false
    }
    return self == other
  }
}
