// Copyright Justin Bishop, 2024

import SwiftUI

@main
struct PodHavenApp: App {
  @State private var alert = Alert.shared

  var body: some Scene {
    WindowGroup {
      ContentView()
        .customAlert($alert.config)
        .task {
          await PlayManager.configureAudioSession()
        }
    }
  }
}
