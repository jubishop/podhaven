// Copyright Justin Bishop, 2024

import Foundation

@Observable @MainActor
final class TabHeights: Sendable {
  private var heights: [Navigation.Tab: CGFloat] = [:]

  subscript(tab: Navigation.Tab) -> CGFloat {
    get {
      self.heights[tab, default: 0]
    }
    set {
      self.heights[tab] = newValue
    }
  }
}
