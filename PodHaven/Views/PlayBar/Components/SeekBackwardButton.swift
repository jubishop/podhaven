// Copyright Justin Bishop, 2025

import FactoryKit
import SwiftUI

struct SeekBackwardButton: View {
  @Injected(\.userSettings) private var userSettings
  @State private var animationTrigger = false

  let action: () -> Void

  var body: some View {
    AppIcon.seekBackward(Int(userSettings.skipBackwardInterval))
      .imageButton {
        animationTrigger.toggle()
        action()
      }
      .symbolEffect(.rotate.counterClockwise, options: .speed(10.0), value: animationTrigger)
  }
}
