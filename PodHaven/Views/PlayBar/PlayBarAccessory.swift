// Copyright Justin Bishop, 2025

import Foundation
import SwiftUI

// Eventually we should replace this with TabViewBottomAccessoryPlacement
struct PlayBarAccessory: View {
  nonisolated static let CoordinateName = "TabRoot"

  @State private var viewModel = PlayBarViewModel()

  private let tabMaxY: CGFloat

  init(tabMaxY: CGFloat) {
    self.tabMaxY = tabMaxY
  }

  var body: some View {
    PlayBar(viewModel: viewModel)
      .onGeometryChange(for: CGFloat.self) { proxy in
        proxy.frame(in: .named(Self.CoordinateName)).maxY
      } action: { newMaxY in
        viewModel.isExpanded = ((tabMaxY - newMaxY) > 40)
      }
  }
}
