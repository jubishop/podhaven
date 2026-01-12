// Copyright Justin Bishop, 2025

import SwiftUI

struct SeekForwardButton: View {
  @State private var animationTrigger = false

  let action: () -> Void

  var body: some View {
    AppIcon.seekForward
      .imageButton {
        animationTrigger.toggle()
        action()
      }
      .symbolEffect(.rotate.clockwise, options: .speed(10.0), value: animationTrigger)
  }
}
