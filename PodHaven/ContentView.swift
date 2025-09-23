// Copyright Justin Bishop, 2025

import FactoryKit
import SwiftUI

struct ContentView: View {
  @InjectedObservable(\.navigation) private var navigation
  @InjectedObservable(\.playState) private var playState

  @State private var playBarHeight: CGFloat = 0
  @State private var rootSafeAreaBottom: CGFloat = 0
  @State private var tabContentBottomInset: CGFloat = 0

  var body: some View {
    ZStack(alignment: .bottom) {
      MainTabView { newInset in
        tabContentBottomInset = newInset
      }
      .onGeometryChange(for: CGFloat.self) { geometry in
        geometry.safeAreaInsets.bottom
      } action: { newInset in
        rootSafeAreaBottom = newInset
      }

      if playState.showPlayBar {
        PlayBar()
          .onGeometryChange(for: CGFloat.self) { geometry in
            geometry.size.height
          } action: { newHeight in
            playBarHeight = newHeight
          }
          .padding(.bottom, tabContentBottomInset - rootSafeAreaBottom)
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
