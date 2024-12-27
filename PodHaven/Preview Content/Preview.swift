// Copyright Justin Bishop, 2024

import Foundation
import SwiftUI

struct Preview<Content: View>: View {
  @State private var alert = Alert.shared

  let content: Content

  init(@ViewBuilder content: () -> Content) {
    self.content = content()
  }

  var body: some View {
    content
      .customAlert($alert.config)
      .task {
        await PodHavenApp.configureAudioSession()
      }
  }
}
