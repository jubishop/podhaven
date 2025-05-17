// Copyright Justin Bishop, 2025

import FactoryKit
import SwiftUI

struct TabContentWithPlayBar<Content: View>: View {
  @State private var playState = Container.shared.playState()

  private let content: Content

  init(@ViewBuilder content: () -> Content) {
    self.content = content()
  }

  var body: some View {
    VStack(spacing: 2) {
      content
      
      if playState.showPlayBar {
        PlayBar()
          .padding(.bottom, 2)
      }
    }
    .tab()
  }
}
