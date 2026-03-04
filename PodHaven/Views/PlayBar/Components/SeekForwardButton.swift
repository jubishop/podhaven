// Copyright Justin Bishop, 2025

import FactoryKit
import SwiftUI

struct SeekForwardButton: View {
  @State private var animationTrigger = false

  let action: () -> Void

  var body: some View {
    AppIcon.seekForward(Int(Container.shared.userSettings().skipForwardInterval))
      .imageButton {
        animationTrigger.toggle()
        action()
      }
      .symbolEffect(.rotate.clockwise, options: .speed(10.0), value: animationTrigger)
  }
}
