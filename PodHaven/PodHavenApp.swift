// Copyright Justin Bishop, 2025

import AVFoundation
import Factory
import SwiftUI

#if !DEBUG
  import Sentry
#endif

@main
struct PodHavenApp: App {
  @State private var alert = Container.shared.alert()

  let refreshManager = Container.shared.refreshManager()
  let playManager = Container.shared.playManager()

  private func configureAudioSession() async {
    do {
      try AVAudioSession.sharedInstance()
        .setCategory(
          .playback,
          mode: .spokenAudio,
          policy: .longFormAudio
        )
      try AVAudioSession.sharedInstance().setMode(.spokenAudio)
    } catch {
      alert.andReport("Failed to initialize the audio session")
    }
  }

  init() {
    #if !DEBUG
      SentrySDK.start { options in
        options.dsn =
          "https://df2c739d3207c6cbc8d0e6f965238234@o4508469263663104.ingest.us.sentry.io/4508469264711681"
        options.enableAutoPerformanceTracing = true
        options.tracesSampleRate = 1.0
        options.profilesSampleRate = 1.0
      }
    #endif
  }

  var body: some Scene {
    WindowGroup {
      ContentView()
        .customAlert($alert.config)
        .environment(alert)
        .task {
          await configureAudioSession()
          await playManager.begin()
          await refreshManager.startBackgroundRefreshing()
        }
    }
  }
}
