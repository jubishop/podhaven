// Copyright Justin Bishop, 2025

import SwiftUI

struct SeekBackwardButton: View {
  @State private var animationTrigger = false

  let action: () -> Void

  var body: some View {
    AppIcon.seekBackward
      .imageButton {
        animationTrigger.toggle()
        action()
      }
      .symbolEffect(.rotate.counterClockwise, options: .speed(10.0), value: animationTrigger)
  }
}
