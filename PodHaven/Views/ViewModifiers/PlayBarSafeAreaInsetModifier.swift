// Copyright Justin Bishop, 2025

import SwiftUI

private struct PlayBarSafeAreaInsetModifier: ViewModifier {
  @Environment(\.playBarSafeAreaInset) private var playBarInset

  func body(content: Content) -> some View {
    if playBarInset > 0 {
      content
        .safeAreaInset(edge: .bottom, spacing: 0) {
          Spacer()
            .frame(height: playBarInset)
            .allowsHitTesting(false)
        }
    } else {
      content
    }
  }
}

extension View {
  func playBarSafeAreaInset() -> some View {
    modifier(PlayBarSafeAreaInsetModifier())
  }
}
