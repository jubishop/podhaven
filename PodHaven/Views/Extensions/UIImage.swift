// Copyright Justin Bishop, 2025

import UIKit

extension UIImage {
  func isVisuallyEqual(to other: UIImage) -> Bool {
    guard self.size == other.size && self.scale == other.scale else { return false }
    guard let selfData = self.pngData(), let otherData = other.pngData() else { return false }

    let sizeDiff = abs(selfData.count - otherData.count)
    let maxDiff = max(selfData.count, otherData.count) / 100  // 1% difference
    return sizeDiff <= maxDiff
  }
}
