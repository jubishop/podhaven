// Copyright Justin Bishop, 2025

import FactoryKit
import Logging
import Sentry
import SwiftUI
import Tagged
import UIKit

// MARK: - AppDelegate

final class AppDelegate: NSObject, UIApplicationDelegate {
  @DynamicInjected(\.cacheBackgroundDelegate) private var cacheBackgroundDelegate
  @DynamicInjected(\.cachePurger) private var cachePurger
  @DynamicInjected(\.playManager) private var playManager
  @DynamicInjected(\.refreshScheduler) private var refreshScheduler

  private static let log: Logger = Log.as("AppDelegate")

  func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
  ) -> Bool {
    AppInfo.initializeEnvironment()
    configureLogging()

    Self.log.debug("Initial environment is: \(AppInfo.environment)")

    refreshScheduler.register()
    cachePurger.register()

    // Enable AirPods/lock screen controls even during background launches.
    // Audio session and command handlers must be configured synchronously.
    do {
      try Container.shared.configureAudioSession()()
      CommandCenter.registerRemoteCommandHandlers()
      Task { await playManager.startStreamConsumers() }
    } catch {
      Self.log.error(error)
    }

    return true
  }

  func application(
    _ application: UIApplication,
    handleEventsForBackgroundURLSession identifier: String,
    completionHandler: @escaping () -> Void
  ) {
    cacheBackgroundDelegate.store(
      id: URLSessionConfiguration.ID(identifier),
      completion: { @MainActor in completionHandler() }
    )
  }

  // MARK: - Logging

  private func configureLogging() {
    switch AppInfo.environment {
    case .appStore, .testFlight, .iPhoneDev, .macDev:
      Self.configureSentry()

      let sharedState = Container.shared.sharedState()
      LoggingSystem.bootstrap { label in
        MultiplexLogHandler([
          OSLogHandler(label: label),
          FileLogHandler(
            label: label,
            fileURL: AppInfo.logFileURL,
            maxFileSizeBytes: 2_000_000,
            targetFileSizeBytes: 1_750_000,
            writeSynchronously: { $0 >= .critical || !sharedState.isActive }
          ),
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
    }
  }

  // MARK: - Scene Phase

  func handleScenePhaseChange(to phase: ScenePhase) {
    if phase == .background {
      FileLogHandler.flush()
    }
  }

  // MARK: - Sentry

  private static func configureSentry() {
    SentrySDK.start { options in
      options.dsn =
        "https://df2c739d3207c6cbc8d0e6f965238234@o4508469263663104.ingest.us.sentry.io/4508469264711681"
      options.sendDefaultPii = true
      options.enableAppHangTracking = false
      options.enableLogs = true
      options.initialScope = { scope in
        scope.setTag(value: AppInfo.gitCommitHash, key: "git-commit-hash")
        return scope
      }
    }
  }
}
