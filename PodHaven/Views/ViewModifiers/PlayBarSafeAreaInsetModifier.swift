// Copyright Justin Bishop, 2025

import SwiftUI

private struct PlayBarSafeAreaInsetModifier: ViewModifier {
  @Environment(\.playBarSafeAreaInset) private var playBarSafeAreaInset

  func body(content: Content) -> some View {
    if playBarSafeAreahInset > 0 {
      content
        .safeAreaInset(edge: .bottom, spacing: 0) {
          Spacer()
            .frame(height: playBarSafeAreaInset)
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
