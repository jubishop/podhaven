// Copyright Justin Bishop, 2025

import Foundation

extension CGFloat {
  func clamped(min: CGFloat?, max: CGFloat?) -> CGFloat {
    var value = self
    if let min { value = Swift.max(value, min) }
    if let max { value = Swift.min(value, max) }
    return value
  }
}
