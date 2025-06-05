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

  @State private var isInitialized = false

  static private let log = Log.as("main")

  var body: some Scene {
    WindowGroup {
      Group {
        if isInitialized {
          ContentView()
            .customAlert($alert.config)
        } else {
          ProgressView("Loading...")
        }
      }
      .task {
        await AppInfo.initializeEnvironment()
        Self.configureLogging()
        isInitialized = true
        Self.configureAudioSession()
        await Container.shared.playManager().start()
        await Container.shared.refreshManager().start()
      }
    }
  }

  // MARK: - System Permissions

  private static func configureAudioSession() {
    let audioSession = AVAudioSession.sharedInstance()
    do {
      try audioSession.setCategory(.playback, mode: .spokenAudio, policy: .longFormAudio)
      try audioSession.setMode(.spokenAudio)
      try audioSession.setActive(true)
    } catch {
      let alert = Container.shared.alert()
      alert("Couldn't get audio permissions") {
        Button("Send Report and Crash") {
          Assert.fatal("Failed to initialize the audio session")
        }
      }
    }
  }

  // MARK: - Logging

  static func configureLogging() {
    switch AppInfo.environment {
    case .iPhone:
      if AppInfo.myPhone {
        configureBugFender()
        configureSentry()

        log.debug("configureLogging: myPhone (OSLogHandler, RemoteLogHandler, CrashReportHandler)")
        LoggingSystem.bootstrap { label in
          MultiplexLogHandler([
            OSLogHandler(label: label),
            RemoteLogHandler(label: label),
            CrashReportHandler(label: label),
          ])
        }
      } else {
        log.debug("configureLogging: not myPhone (OSLogHandler)")
        LoggingSystem.bootstrap(OSLogHandler.init)
      }
    case .preview:
      log.debug("configureLogging: preview (PrintLogHandler)")
      LoggingSystem.bootstrap(PrintLogHandler.init)
    case .simulator, .mac, .appStore:
      log.debug("configureLogging: simulator/mac/appStore (OSLogHandler)")
      LoggingSystem.bootstrap(OSLogHandler.init)
    }
  }

  private static func configureBugFender() {
    Bugfender.activateLogger("DHXOFyzIYy2lzznaFpku5oXaiGwqqDXE")
    Bugfender.setPrintToConsole(false)
    Bugfender.enableCrashReporting()
  }

  private static func configureSentry() {
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
