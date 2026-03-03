// Copyright Justin Bishop, 2026

import SwiftUI

enum TruncatingRole {
  case item
  case overflow
}

struct TruncatingRoleKey: LayoutValueKey {
  static let defaultValue: TruncatingRole = .item
}

// A vertical stack that places children top-to-bottom, truncating any
// that don't fit in the available height. When items are truncated, it
// shows the single overflow indicator (tagged .overflow) at the bottom.
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
    let totalHeight =
      subviews
      .filter { $0[TruncatingRoleKey.self] == .item }
      .reduce(CGFloat(0)) { sum, sub in
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
    let items = subviews.filter { $0[TruncatingRoleKey.self] == .item }
    let overflows = subviews.filter { $0[TruncatingRoleKey.self] == .overflow }
    Assert.precondition(!items.isEmpty, "TruncatingVStack requires at least one .item subview")
    Assert.precondition(
      overflows.count <= 1,
      "TruncatingVStack expects at most one .overflow subview"
    )
    let overflow = overflows.first

    let itemSizes = items.map {
      $0.sizeThatFits(ProposedViewSize(width: bounds.width, height: nil))
    }
    let overflowHeight =
      overflow?
      .sizeThatFits(ProposedViewSize(width: bounds.width, height: nil))
      .height ?? 0

    // Count how many items fit, reserving space for overflow
    var fittedCount = 0
    var usedHeight: CGFloat = 0
    for size in itemSizes {
      if usedHeight + size.height + overflowHeight > bounds.height { break }
      fittedCount += 1
      usedHeight += size.height
    }
    fittedCount = max(min(1, items.count), fittedCount)

    // Place fitted items
    var y = bounds.minY
    for (index, item) in items.enumerated() {
      if index >= fittedCount {
        item.place(at: CGPoint(x: -10000, y: -10000), proposal: .zero)
        continue
      }
      let size = itemSizes[index]
      item.place(
        at: CGPoint(x: bounds.minX, y: y),
        proposal: ProposedViewSize(width: bounds.width, height: size.height)
      )
      y += size.height
    }

    // Pin overflow to the bottom
    if let overflow {
      let size = overflow.sizeThatFits(
        ProposedViewSize(width: bounds.width, height: nil)
      )
      overflow.place(
        at: CGPoint(x: bounds.minX, y: bounds.maxY - size.height),
        proposal: ProposedViewSize(width: bounds.width, height: size.height)
      )
    }
  }
}
