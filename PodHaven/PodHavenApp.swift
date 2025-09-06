// Copyright Justin Bishop, 2025

import AVFoundation
import FactoryKit
import Logging
import Sentry
import SwiftUI

@main
struct PodHavenApp: App {
  @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

  @InjectedObservable(\.alert) private var alert
  @InjectedObservable(\.sheet) private var sheet
  @DynamicInjected(\.cacheManager) private var cacheManager
  @DynamicInjected(\.notifications) private var notifications
  @DynamicInjected(\.playManager) private var playManager
  @DynamicInjected(\.refreshManager) private var refreshManager
  @DynamicInjected(\.repo) private var repo
  @DynamicInjected(\.shareService) private var shareService

  @State private var isInitialized = false

  private static let log = Log.as("Main")

  var body: some Scene {
    WindowGroup {
      Group {
        if isInitialized {
          ContentView()
            .customAlert($alert.config)
            .customSheet($sheet.config)
        } else {
          ProgressView("Loading...")
        }
      }
      .task {
        await AppInfo.initializeEnvironment()
        configureLogging()
        Self.log.debug("Environment is: \(AppInfo.environment)")
        Self.log.debug("Device identifier is: \(AppInfo.deviceIdentifier)")

        isInitialized = true

        if AppInfo.environment != .testing {
          startMemoryWarningMonitoring()
          await playManager.start()
          await refreshManager.start()
          do {
            try await cacheManager.start()
          } catch {
            Self.log.error(error)
            alert(ErrorKit.coreMessage(for: error))
          }
        }
      }
      .onOpenURL { url in
        Self.log.info("Received incoming URL: \(url)")
        Task {
          await handleIncomingURL(url)
        }
      }
    }
  }

  // MARK: - URL Handling

  private func handleIncomingURL(_ url: URL) async {
    if ShareService.isShareURL(url) {
      do {
        try await shareService.handleIncomingURL(url)
      } catch {
        Self.log.error(error)
        alert(ErrorKit.message(for: error))
      }
    } else {
      Self.log.warning("Incoming URL: \(url) is not supported")
      alert("Incoming URL: \(url) is not supported")
    }
  }

  // MARK: - Memory Monitoring

  private func startMemoryWarningMonitoring() {
    Task {
      for await _ in notifications(UIApplication.didReceiveMemoryWarningNotification) {
        Self.log.warning("System memory warning received")
        if AppInfo.myDevice {
          alert("Memory warning received")
        }
      }
    }
  }

  // MARK: - Logging

  private func configureLogging() {
    switch AppInfo.environment {
    case .testFlight, .iPhoneDev, .macDev:
      configureSentry()

      LoggingSystem.bootstrap { label in
        MultiplexLogHandler([
          OSLogHandler(label: label),
          FileLogHandler(label: label),
          SentryLogHandler(label: label),
          CrashReportHandler(label: label),
        ])
      }
      Self.log.debug("configureLogging: OSLog, FileLog, CrashReport")
    case .preview:
      LoggingSystem.bootstrap(PrintLogHandler.init)
      Self.log.debug("configureLogging: PrintLog")
    case .simulator, .testing:
      LoggingSystem.bootstrap(OSLogHandler.init)
      Self.log.debug("configureLogging: OSLog")
    case .appStore:
      LoggingSystem.bootstrap(SwiftLogNoOpLogHandler.init)
      Self.log.debug("configureLogging: SwiftLogNoOp")
    }
  }

  private func configureSentry() {
    SentrySDK.start { options in
      options.dsn =
        "https://df2c739d3207c6cbc8d0e6f965238234@o4508469263663104.ingest.us.sentry.io/4508469264711681"
      options.sendDefaultPii = true
      options.enableAppHangTracking = false
      options.experimental.enableLogs = true
    }
  }
}
