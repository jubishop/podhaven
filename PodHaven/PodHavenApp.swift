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

  init() {
    Task {
      await Self.configureLogging()
      Self.configureAudioSession()
      await Container.shared.playState().start()
      await Container.shared.playManager().start()
      await Container.shared.refreshManager().start()
    }
  }

  var body: some Scene {
    WindowGroup {
      ContentView()
        .customAlert($alert.config)
    }
  }

  private static func configureLogging() async {
    #if !DEBUG
    SentrySDK.start { options in
      options.dsn =
        "https://df2c739d3207c6cbc8d0e6f965238234@o4508469263663104.ingest.us.sentry.io/4508469264711681"
      options.enableAutoPerformanceTracing = true
      options.tracesSampleRate = 1.0
      options.profilesSampleRate = 1.0
    }
    #endif

    let environment = await Container.shared.appInfo().environment
    if case .preview = environment {
      LoggingSystem.bootstrap(PrintLogHandler.init)
    } else {
      LoggingSystem.bootstrap(OSLogHandler.init)
    }
  }

  private static func configureAudioSession() {
    let audioSession = AVAudioSession.sharedInstance()
    do {
      try audioSession.setCategory(.playback, mode: .spokenAudio, policy: .longFormAudio)
      try audioSession.setMode(.spokenAudio)
      try audioSession.setActive(true)
    } catch {
      Assert.fatal("Failed to initialize the audio session")
    }
  }
}
