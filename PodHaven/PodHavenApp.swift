// Copyright Justin Bishop, 2025

import AVFoundation
import FactoryKit
import Logging
import Sentry
import SwiftUI

@main
struct PodHavenApp: App {
  @InjectedObservable(\.alert) private var alert

  @DynamicInjected(\.playManager) private var playManager
  @DynamicInjected(\.refreshManager) private var refreshManager

  @State private var isInitialized = false

  private static let log = Log.as("Main")

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
        configureLogging()
        isInitialized = true
        configureAudioSession()
        await playManager.start()
        await refreshManager.start()
      }
    }
  }

  // MARK: - System Permissions

  private func configureAudioSession() {
    let audioSession = AVAudioSession.sharedInstance()
    do {
      try audioSession.setCategory(.playback, mode: .spokenAudio, policy: .longFormAudio)
      try audioSession.setMode(.spokenAudio)
      try audioSession.setActive(true)
    } catch {
      alert("Couldn't get audio permissions") {
        Button("Send Report and Crash") {
          Assert.fatal("Failed to initialize the audio session")
        }
      }
    }
  }

  // MARK: - Logging

  private func configureLogging() {
    switch AppInfo.environment {
    case .iPhone:
      configureSentry()

      LoggingSystem.bootstrap { label in
        MultiplexLogHandler([
          OSLogHandler(label: label),
          FileLogHandler(label: label),
          CrashReportHandler(label: label),
        ])
      }
      Self.log.debug("configureLogging: iPhone (OSLogHandler, FileLogHandler, CrashReportHandler)")
    case .preview:
      LoggingSystem.bootstrap(PrintLogHandler.init)
      Self.log.debug("configureLogging: preview (PrintLogHandler)")
    case .simulator, .mac, .appStore, .testing:
      LoggingSystem.bootstrap(OSLogHandler.init)
      Self.log.debug("configureLogging: simulator/mac/appStore/testing (OSLogHandler)")
    }
  }

  private func configureSentry() {
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
