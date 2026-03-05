// Copyright Justin Bishop, 2026

import SwiftUI

// A vertical stack that places children top-to-bottom, truncating any
// that don't fit in the available height.
struct TruncatingVStack: Layout {
  func sizeThatFits(
    proposal: ProposedViewSize,
    subviews: Subviews,
    cache: inout ()
  ) -> CGSize {
    let width = proposal.width ?? 0
    if let height = proposal.height {
      return CGSize(width: width, height: height)
    }
    let totalHeight = subviews.reduce(CGFloat(0)) { sum, sub in
      sum + sub.sizeThatFits(ProposedViewSize(width: width, height: nil)).height
    }
    return CGSize(width: width, height: totalHeight)
  }

  func placeSubviews(
    in bounds: CGRect,
    proposal: ProposedViewSize,
    subviews: Subviews,
    cache: inout ()
  ) {
    let sizes = subviews.map {
      $0.sizeThatFits(ProposedViewSize(width: bounds.width, height: nil))
    }

    var fittedCount = 0
    var usedHeight: CGFloat = 0
    for size in sizes {
      if usedHeight + size.height > bounds.height { break }
      fittedCount += 1
      usedHeight += size.height
    }
    fittedCount = max(min(1, subviews.count), fittedCount)

    var y = bounds.minY
    for (index, subview) in subviews.enumerated() {
      if index >= fittedCount {
        subview.place(at: CGPoint(x: -10000, y: -10000), proposal: .zero)
        continue
      }
      let size = sizes[index]
      subview.place(
        at: CGPoint(x: bounds.minX, y: y),
        proposal: ProposedViewSize(width: bounds.width, height: size.height)
      )
      y += size.height
    }
  }
}
