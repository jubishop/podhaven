// Copyright Justin Bishop, 2025

import AVFoundation
import FactoryKit
import Logging
import SwiftUI

#if !DEBUG
import Sentry
#endif

@main
struct PodHavenApp: App {
  @InjectedObservable(\.alert) private var alert
  @DynamicInjected(\.playState) private var playState
  @DynamicInjected(\.refreshManager) private var refreshManager
  private var playManager: PlayManager { get async { await Container.shared.playManager() } }

  private var audioSession: AVAudioSession { AVAudioSession.sharedInstance() }

  private func configureAudioSession() async {
    do {
      try audioSession.setCategory(.playback, mode: .spokenAudio, policy: .longFormAudio)
      try audioSession.setMode(.spokenAudio)
      try audioSession.setActive(true)
    } catch {
      alert("Failed to initialize the audio session")
    }
  }

  init() {
    #if DEBUG
    LoggingSystem.bootstrap(ConsoleLogHandler.init)
    #else
    LoggingSystem.bootstrap(FileLogHandler.init)
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
          await playState.start()
          await playManager.start()
          await refreshManager.start()
        }
    }
  }
}
