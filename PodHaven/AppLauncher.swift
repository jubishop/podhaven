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
  @DynamicInjected(\.embeddingProcessor) private var embeddingProcessor
  @DynamicInjected(\.notifications) private var notifications
  @DynamicInjected(\.playManager) private var playManager
  @DynamicInjected(\.recommendationEngine) private var recommendationEngine
  @DynamicInjected(\.refreshScheduler) private var refreshScheduler
  @DynamicInjected(\.stateManager) private var stateManager
  @DynamicInjected(\.widgetSnapshotWriter) private var widgetSnapshotWriter

  private var alert: Alert { get async { await Container.shared.alert() } }
  private var taskPriority: @Sendable (TaskPriority) -> TaskPriority? {
    Container.shared.taskPriority()
  }
  private var userNotificationManager: UserNotificationManager {
    Container.shared.userNotificationManager()
  }

  private static let log = Log.as("AppLauncher")
  private let prepareForPlaybackOnce = AsyncOnce()
  private let prepareForForegroundOnce = AsyncOnce()
  private let startSystemMonitoringOnce = Once()

  fileprivate init() {}

  // MARK: - Bootstrap

  // Synchronous early-launch work. Called from AppDelegate.didFinishLaunchingWithOptions.
  @MainActor func bootstrap() {
    AppInfo.initializeEnvironment()
    guard AppInfo.environment != .preview else { return }

    configureLogging()

    // Force DB initialization so schema migrations run immediately.
    _ = Container.shared.appDB()

    Self.log.debug(
      """
      Initial environment is: \(AppInfo.environment), 
      state: \(UIApplication.shared.applicationState)
      """
    )

    refreshScheduler.register()
    cachePurger.register()
    embeddingProcessor.register()

    // Audio session and command handlers must be configured synchronously
    // to enable AirPods/lock screen controls even during background launches.
    do {
      try Container.shared.configureAudioSession()()
      CommandCenter.registerRemoteCommandHandlers()
    } catch {
      Self.log.caughtError("bootstrap: failed to configure audio session", error)
    }
  }

  // MARK: - Playback

  // Minimum initialization for audio playback from a background launch.
  func prepareForPlayback() async {
    await prepareForPlaybackOnce.run {
      Self.log.info("Preparing for background audio playback")
      self.stateManager.start()
      await self.playManager.start()
      self.widgetSnapshotWriter.start()
    }
  }

  // MARK: - Foreground

  // Full initialization for the foreground UI experience.
  // Called when the app scene becomes active.
  func prepareForForeground() async {
    await prepareForForegroundOnce.run {
      Self.log.info("Preparing for foreground")

      await AppInfo.finalizeEnvironment()
      await Self.applySentryEnvironment()
      guard !Task.isCancelled else { return }

      await self.userNotificationManager.initialize()
      guard !Task.isCancelled else { return }

      Self.log.debug("Device identifier is: \(AppInfo.deviceIdentifier)")
      Self.log.debug("My device?: \(AppInfo.myDevice)")
      Self.log.debug("Final environment is: \(AppInfo.environment)")
      Self.log.debug("Build version: \(AppInfo.version) (\(AppInfo.buildNumber))")
      Self.log.debug("Git commit hash is: \(AppInfo.gitCommitHash)")

      // Ensure playback subsystems are started (no-op if already done by an intent)
      await self.prepareForPlayback()
      guard AppInfo.environment != .testing else { return }
      guard !Task.isCancelled else { return }

      // Start all other services
      self.cacheManager.start()
      self.recommendationEngine.start()

      // System monitoring
      self.startSystemMonitoring()
    }
  }

  // MARK: - System Monitoring

  private func startSystemMonitoring() {
    startSystemMonitoringOnce.run {
      Task(priority: taskPriority(.utility)) {
        for await _ in self.notifications(UIApplication.didReceiveMemoryWarningNotification) {
          Self.log.warning("System memory warning received")

          if AppInfo.myDevice {
            await self.alert("Memory warning received")
          }
        }
      }

      Task(priority: taskPriority(.utility)) {
        for await _ in self.notifications(ProcessInfo.thermalStateDidChangeNotification) {
          let state =
            switch ProcessInfo.processInfo.thermalState {
            case .nominal: "nominal"
            case .fair: "fair"
            case .serious: "serious"
            case .critical: "critical"
            @unknown default: "unknown"
            }
          Self.log.warning("Thermal state changed to: \(state)")
        }
      }
    }
  }

  // MARK: - Logging

  private func configureLogging() {
    switch AppInfo.environment {
    case .deployed, .appStore, .testFlight, .iPhoneDev, .macDev:
      Self.configureSentry()

      let sharedState = Container.shared.sharedState()
      LoggingSystem.bootstrap { label in
        MultiplexLogHandler([
          OSLogHandler(label: label),
          FileLogHandler(
            label: label,
            fileURL: AppInfo.logFileURL,
            maxFileSizeBytes: 3_000_000,
            targetFileSizeBytes: 2_000_000,
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

  @MainActor private static func applySentryEnvironment() {
    SentrySDK.configureScope { scope in
      scope.setEnvironment(AppInfo.environment.rawValue)
    }
  }

  private static func configureSentry() {
    SentrySDK.start { options in
      options.dsn =
        "https://df2c739d3207c6cbc8d0e6f965238234@o4508469263663104.ingest.us.sentry.io/4508469264711681"
      options.environment = AppInfo.environment.rawValue
      options.sendDefaultPii = true
      options.enableAppHangTracking = true
      options.enableLogs = true
      options.initialScope = { scope in
        scope.setTag(value: AppInfo.gitCommitHash, key: "git-commit-hash")
        scope.setUser(User(userId: AppInfo.deviceIdentifier))
        return scope
      }
    }
  }
}
