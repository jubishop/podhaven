// Copyright Justin Bishop, 2025

import Foundation
import SwiftUI

// Eventually we should replace this with TabViewBottomAccessoryPlacement
struct PlayBarAccessory: View {
  nonisolated static let CoordinateName = "TabRoot"

  private static let log = Log.as(LogSubsystem.PlayBar.accessory)

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
        Self.log.trace("New maxY: \(newMaxY)")
        viewModel.isExpanded = ((tabMaxY - newMaxY) > 40)
      }
  }
}
