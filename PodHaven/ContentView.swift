// Copyright Justin Bishop, 2025

import FactoryKit
import SwiftUI

struct ContentView: View {
  @InjectedObservable(\.playState) private var playState

  @State private var playBarHeight: CGFloat = 0

  @State private var mainTabSafeAreaInset: CGFloat = 0
  @State private var tabContentSafeAreaInset: CGFloat = 0

  var body: some View {
    ZStack(alignment: .bottom) {
      MainTabView(tabContentSafeAreaInset: $tabContentSafeAreaInset)
        .onGeometryChange(for: CGFloat.self) { geometry in
          geometry.safeAreaInsets.bottom
        } action: { newInset in
          mainTabSafeAreaInset = newInset
        }

      if playState.showPlayBar {
        PlayBar()
          .onGeometryChange(for: CGFloat.self) { geometry in
            geometry.size.height
          } action: { newHeight in
            playBarHeight = newHeight
          }
          .padding(.bottom, tabContentSafeAreaInset - mainTabSafeAreaInset)
      }
    }
    .environment(\.playBarSafeAreaInset, playState.showPlayBar ? playBarHeight : 0)
  }
}

#if DEBUG
#Preview {
  ContentView()
    .preview()
}
#endif
