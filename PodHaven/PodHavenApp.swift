// Copyright Justin Bishop, 2025

import AVFoundation
import BugfenderSDK
import FactoryKit
import Logging
import Sentry
import SwiftUI

@main
struct PodHavenApp: App {
  @InjectedObservable(\.alert) private var alert

  init() {
    Task {
      await Self.configureLogging()
      Self.configureAudioSession()
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
    let environment = await Container.shared.appInfo().environment
    switch environment {
    case .appStore:
      break  // Nothing so app is stable and fast
    case .iPhone:
      configureBugFender()
      configureSentry(environment)

      LoggingSystem.bootstrap { label in
        MultiplexLogHandler([
          OSLogHandler(label: label),
          RemoteLogHandler(label: label),
          CrashReportHandler(),
        ])
      }
    case .preview:
      LoggingSystem.bootstrap(PrintLogHandler.init)
    case .simulator, .mac:
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

  private static func configureBugFender() {
    Bugfender.activateLogger("DHXOFyzIYy2lzznaFpku5oXaiGwqqDXE")
    Bugfender.setPrintToConsole(false)
    Bugfender.enableCrashReporting()  // optional, log crashes automatically
  }

  private static func configureSentry(_ environment: EnvironmentType) {
    SentrySDK.start { options in
      options.dsn =
        "https://df2c739d3207c6cbc8d0e6f965238234@o4508469263663104.ingest.us.sentry.io/4508469264711681"

      // Maximum info
      options.sendDefaultPii = true
      options.attachScreenshot = true
      options.attachViewHierarchy = true

      // Excessive crap
      options.enableAppHangTracking = false
      options.enableSwizzling = false
    }
  }
}
