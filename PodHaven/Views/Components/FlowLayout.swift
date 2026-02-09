// Copyright Justin Bishop, 2026

import SwiftUI

struct FlowLayout: Layout {
  var horizontalSpacing: CGFloat
  var verticalSpacing: CGFloat

  init(horizontalSpacing: CGFloat = 8, verticalSpacing: CGFloat = 8) {
    self.horizontalSpacing = horizontalSpacing
    self.verticalSpacing = verticalSpacing
  }

  func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
    arrange(in: proposal, subviews: subviews).size
  }

  func placeSubviews(
    in bounds: CGRect,
    proposal: ProposedViewSize,
    subviews: Subviews,
    cache: inout ()
  ) {
    let result = arrange(
      in: ProposedViewSize(width: bounds.width, height: bounds.height),
      subviews: subviews
    )
    for (index, position) in result.positions.enumerated() {
      subviews[index]
        .place(
          at: CGPoint(x: bounds.minX + position.x, y: bounds.minY + position.y),
          proposal: .unspecified
        )
    }
  }

  private func arrange(in proposal: ProposedViewSize, subviews: Subviews) -> (
    positions: [CGPoint], size: CGSize
  ) {
    var positions: [CGPoint] = []
    var x: CGFloat = 0
    var y: CGFloat = 0
    var rowHeight: CGFloat = 0
    var maxLineWidth: CGFloat = 0
    let maxWidth = proposal.width ?? .greatestFiniteMagnitude

    for subview in subviews {
      let size = subview.sizeThatFits(.unspecified)
      if x + size.width > maxWidth && x > 0 {
        maxLineWidth = max(maxLineWidth, x - horizontalSpacing)
        x = 0
        y += rowHeight + verticalSpacing
        rowHeight = 0
      }
      positions.append(CGPoint(x: x, y: y))
      x += size.width + horizontalSpacing
      rowHeight = max(rowHeight, size.height)
    }

    maxLineWidth = max(maxLineWidth, x - horizontalSpacing)
    let finalWidth = proposal.width ?? max(maxLineWidth, 0)
    return (positions: positions, size: CGSize(width: finalWidth, height: y + rowHeight))
  }
}
