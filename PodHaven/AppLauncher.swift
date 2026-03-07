// Copyright Justin Bishop, 2026

import FactoryKit
import Logging
import Sentry
import UIKit

extension Container {
  var appLauncher: Factory<AppLauncher> {
    Factory(self) { AppLauncher() }.scope(.cached)
  }
}

struct AppLauncher: Sendable {
  @DynamicInjected(\.cacheManager) private var cacheManager
  @DynamicInjected(\.cachePurger) private var cachePurger
  @DynamicInjected(\.notifications) private var notifications
  @DynamicInjected(\.playManager) private var playManager
  @DynamicInjected(\.refreshScheduler) private var refreshScheduler
  @DynamicInjected(\.stateManager) private var stateManager
  @DynamicInjected(\.widgetSnapshotWriter) private var widgetSnapshotWriter

  private var alert: Alert { get async { await Container.shared.alert() } }
  private var userNotificationManager: UserNotificationManager {
    Container.shared.userNotificationManager()
  }

  private static let log = Log.as("AppLauncher")

  fileprivate init() {}

  // MARK: - Bootstrap

  // Synchronous early-launch work. Called from AppDelegate.didFinishLaunchingWithOptions.
  @MainActor func bootstrap() {
    AppInfo.initializeEnvironment()
    configureLogging()

    Self.log.debug("Initial environment is: \(AppInfo.environment)")

    refreshScheduler.register()
    cachePurger.register()

    // Audio session and command handlers must be configured synchronously
    // to enable AirPods/lock screen controls even during background launches.
    do {
      try Container.shared.configureAudioSession()()
      CommandCenter.registerRemoteCommandHandlers()
      Task { await playManager.startStreamConsumers() }
    } catch {
      Self.log.error(error)
    }
  }

  // MARK: - Playback

  // Minimum initialization for audio playback from a background launch.
  // Called from widget intents when the app may not have a foreground scene.
  func prepareForPlayback() async {
    guard Function.neverCalled() else { return }

    Self.log.info("Preparing for background audio playback")
    stateManager.start()
    widgetSnapshotWriter.start()
    await playManager.start()
  }

  // MARK: - Foreground

  // Full initialization for the foreground UI experience.
  // Called when the app scene becomes active.
  func prepareForForeground() async {
    guard Function.neverCalled() else { return }

    Self.log.info("Preparing for foreground")

    await AppInfo.finalizeEnvironment()
    guard !Task.isCancelled else { return }

    await userNotificationManager.initialize()
    guard !Task.isCancelled else { return }

    Self.log.debug("Device identifier is: \(AppInfo.deviceIdentifier)")
    Self.log.debug("My device?: \(AppInfo.myDevice)")
    Self.log.debug("Final environment is: \(AppInfo.environment)")
    Self.log.debug("Build version: \(AppInfo.version) (\(AppInfo.buildNumber))")

    // Ensure playback subsystems are started (no-op if already done by an intent)
    stateManager.start()
    widgetSnapshotWriter.start()

    guard AppInfo.environment != .testing else { return }

    await playManager.start()
    guard !Task.isCancelled else { return }

    cacheManager.start()
    refreshScheduler.start()
    cachePurger.start()

    startMemoryWarningMonitoring()
  }

  // MARK: - Memory Monitoring

  private func startMemoryWarningMonitoring() {
    guard Function.neverCalled() else { return }

    Task {
      for await _ in notifications(UIApplication.didReceiveMemoryWarningNotification) {
        Self.log.warning("System memory warning received")

        if AppInfo.myDevice {
          await alert("Memory warning received")
        }
      }
    }
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

  // MARK: - Sentry

  private static func configureSentry() {
    SentrySDK.start { options in
      options.dsn =
        "https://df2c739d3207c6cbc8d0e6f965238234@o4508469263663104.ingest.us.sentry.io/4508469264711681"
      options.sendDefaultPii = true
      options.enableAppHangTracking = true
      options.enableLogs = true
      options.experimental.enableSessionReplayInUnreliableEnvironment = true
      options.initialScope = { scope in
        scope.setTag(value: AppInfo.gitCommitHash, key: "git-commit-hash")
        return scope
      }
    }
  }
}
