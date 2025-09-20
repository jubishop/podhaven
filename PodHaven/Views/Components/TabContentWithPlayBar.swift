// Copyright Justin Bishop, 2025

import FactoryKit
import SwiftUI

struct TabContentWithPlayBar<Content: View>: View {
  @InjectedObservable(\.playState) private var playState

  @State private var playBarHeight: CGFloat = 0

  private let content: Content

  init(@ViewBuilder content: () -> Content) {
    self.content = content()
  }

  var body: some View {
    ZStack(alignment: .bottom) {
      content
        .environment(\.playBarSafeAreaInset, playBarHeight)
        .playBarSafeAreaInset()

      if playState.showPlayBar {
        PlayBar()
          .onGeometryChange(for: CGFloat.self) { geometry in
            geometry.size.height
          } action: { newSize in
            playBarHeight = newSize
          }
          .padding(.bottom, 2)
      }
    }
    .onChange(of: playState.showPlayBar) {
      if !playState.showPlayBar { playBarHeight = 0 }
    }
  }
}
