// Copyright Justin Bishop, 2025

import Foundation
import SwiftUI

// Eventually we should replace this with TabViewBottomAccessoryPlacement
struct PlayBarAccessory: View {
  nonisolated static let CoordinateName = "TabRoot"

  @State private var isExpanded = true

  private let tabMaxY: CGFloat

  init(tabMaxY: CGFloat) {
    self.tabMaxY = tabMaxY
  }

  var body: some View {
    PlayBar(isExpanded: isExpanded)
      .onGeometryChange(for: CGFloat.self) { proxy in
        proxy.frame(in: .named(Self.CoordinateName)).maxY
      } action: { newMaxY in
        isExpanded = (tabMaxY - newMaxY) > 40
      }
  }
}
