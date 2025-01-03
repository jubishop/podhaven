// Copyright Justin Bishop, 2025

import AVFoundation
import Sentry
import SwiftUI

@main
struct PodHavenApp: App {
  @State private var alert = Alert.shared

  static func configureAudioSession() async {
    do {
      try AVAudioSession.sharedInstance()
        .setCategory(
          .playback,
          mode: .spokenAudio,
          policy: .longFormAudio
        )
      try AVAudioSession.sharedInstance().setMode(.spokenAudio)
      await PlayManager.shared.resume()
    } catch {
      Alert.shared("Failed to initialize the audio session")
    }
  }

  init() {
    SentrySDK.start { options in
      options.dsn =
        "https://df2c739d3207c6cbc8d0e6f965238234@o4508469263663104.ingest.us.sentry.io/4508469264711681"
      options.enableAutoPerformanceTracing = true
      options.tracesSampleRate = 1.0
      options.profilesSampleRate = 1.0
    }
  }

  var body: some Scene {
    WindowGroup {
      ContentView()
        .customAlert($alert.config)
        .task {
          await Self.configureAudioSession()
        }
    }
  }
}
