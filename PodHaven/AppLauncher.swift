// Copyright Justin Bishop, 2026

import AVFoundation
import FactoryKit
import Logging
import MetricKit
import Sentry
import SwiftUI
import UIKit

protocol SentryScopeConfiguring: AnyObject {
  func setTag(value: String, key: String)
  func setUser(_ user: Sentry.User?)
  func addAttachment(_ attachment: Sentry.Attachment)
}

extension Sentry.Scope: SentryScopeConfiguring {}

extension Container {
  var appLauncher: Factory<AppLauncher> {
    Factory(self) { AppLauncher() }.scope(.cached)
  }
}

struct AppLauncher: Sendable {
  @DynamicInjected(\.cacheManager) private var cacheManager
  @DynamicInjected(\.cachePurger) private var cachePurger
  @DynamicInjected(\.embeddingProcessor) private var embeddingProcessor
  @DynamicInjected(\.publisherTranscriptProcessor) private var publisherTranscriptProcessor
  @DynamicInjected(\.transcriptionProcessor) private var transcriptionProcessor
  @DynamicInjected(\.notifications) private var notifications
  @DynamicInjected(\.playManager) private var playManager
  @DynamicInjected(\.recommendationEngine) private var recommendationEngine
  @DynamicInjected(\.refreshScheduler) private var refreshScheduler
  @DynamicInjected(\.stateManager) private var stateManager
  @DynamicInjected(\.thermalPressureMonitor) private var thermalPressureMonitor
  @DynamicInjected(\.transcriptionAvailability) private var transcriptionAvailability
  @DynamicInjected(\.widgetSnapshotWriter) private var widgetSnapshotWriter

  private var alert: Alert { get async { await Container.shared.alert() } }
  private var taskPriority: @Sendable (TaskPriority?) -> TaskPriority? {
    Container.shared.taskPriority()
  }
  private var userNotificationManager: UserNotificationManager {
    Container.shared.userNotificationManager()
  }

  private static let log = Log.as("AppLauncher")
  private let prepareForPlaybackOnce = AsyncOnce()
  private let prepareForForegroundOnce = AsyncOnce()
  private let startSystemMonitoringOnce = Once()

  // MXMetricManager holds subscribers weakly, so this must outlive registration.
  private let metricKitMonitor = MetricKitMonitor()

  fileprivate init() {}

  // MARK: - Bootstrap

  @MainActor func bootstrap() {
    AppInfo.initializeEnvironment()
    guard AppInfo.environment != .preview else { return }

    configureLogging()
    guard AppInfo.environment != .testing else { return }

    // Registered here rather than in the foreground-gated startSystemMonitoring
    // so background-only launches still capture exit metrics.
    MXMetricManager.shared.add(metricKitMonitor)
    Self.log.debug("Registered MetricKit subscriber")

    // Force DB initialization so schema migrations run immediately.
    Container.shared.initializeAppDB()

    thermalPressureMonitor.start()

    Self.log.debug(
      """
      Initial environment is: \(AppInfo.environment), \
      state: \(UIApplication.shared.applicationState)
      """
    )

    // Background-only launches (Siri, AirPods intents) may never foreground,
    // so kick off finalize here too — `prepareForForeground` awaits the same
    // AsyncOnce when it runs.
    Task {
      await AppInfo.finalizeEnvironment()
      Self.applySentryEnvironment()
    }

    refreshScheduler.register()
    cachePurger.register()
    embeddingProcessor.register()
    publisherTranscriptProcessor.register()
    transcriptionProcessor.register()

    // Subscribe before audio session config so a mediaservicesd respawn during
    // launch isn't missed (Apple guidance for mediaServicesWereResetNotification).
    playManager.startStreamConsumers()

    // Must be synchronous so AirPods/lock-screen controls register before iOS
    // evaluates background-launch capability. Sync failure falls back to the
    // async retry factory.
    do {
      let session = AVAudioSession.sharedInstance()
      try session.setCategory(.playback, mode: .spokenAudio, policy: .longFormAudio)
      try session.setMode(.spokenAudio)
      CommandCenter.registerRemoteCommandHandlers()
    } catch {
      Self.log.caughtError(
        "bootstrap: synchronous audio session config failed, scheduling async retry",
        error
      )
      Task {
        // Give mediaservicesd a moment to respawn before the factory's first attempt,
        // since the sync call just confirmed it's down.
        try? await Container.shared.sleeper().sleep(for: .milliseconds(250))
        guard await Container.shared.configureAudioSession()() else { return }
        CommandCenter.registerRemoteCommandHandlers()
      }
    }
  }

  // MARK: - Playback

  func prepareForPlayback() async {
    await prepareForPlaybackOnce.run {
      Self.log.info("Preparing for background audio playback")
      self.stateManager.start()
      await self.playManager.start()
      self.widgetSnapshotWriter.start()
    }
  }

  // MARK: - Foreground

  func prepareForForeground() async {
    await prepareForForegroundOnce.run {
      Self.log.info("Preparing for foreground")

      await AppInfo.finalizeEnvironment()
      await Self.applySentryEnvironment()
      guard AppInfo.environment != .testing else { return }
      guard !Task.isCancelled else { return }

      let transcriptionAvailability = self.transcriptionAvailability
      Task(priority: self.taskPriority(.utility)) {
        await transcriptionAvailability.prepare()
      }

      await self.userNotificationManager.initialize()
      guard !Task.isCancelled else { return }

      Self.log.debug("Device identifier is: \(AppInfo.deviceIdentifier)")
      Self.log.debug("My device?: \(AppInfo.myDevice)")
      Self.log.debug("Final environment is: \(AppInfo.environment)")
      Self.log.debug("Build version: \(AppInfo.version) (\(AppInfo.buildNumber))")
      Self.log.debug("Git commit hash is: \(AppInfo.gitCommitHash)")

      // No-op if an intent already triggered prepareForPlayback during the cold launch.
      await self.prepareForPlayback()
      guard !Task.isCancelled else { return }

      self.cacheManager.start()
      self.recommendationEngine.start()

      self.startSystemMonitoring()
    }

    guard AppInfo.environment != .testing else { return }
    guard !Task.isCancelled else { return }
    await playManager.restorePersistedEpisodeForForeground()
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
    }
  }

  // MARK: - Logging

  private func configureLogging() {
    switch AppInfo.environment {
    case .deployed, .appStore, .testFlight:
      Self.configureSentry()
      Self.bootstrapOSLogAndFileLog { label in
        [SentryLogHandler(label: label), CrashReportHandler(label: label)]
      }
      Self.log.debug(
        """
        configureLogging: OSLog, FileLog, CrashReport; Sentry recent log attachments configured: \
        appLimitBytes=\(AppInfo.recentLogMaxFileSizeBytes), \
        widgetLimitBytes=\(WidgetInfo.recentLogMaxFileSizeBytes)
        """
      )
    case .preview:
      LoggingSystem.bootstrap(PrintLogHandler.init)
      Self.log.debug("configureLogging: PrintLog")
    case .simulator, .iPhoneDev, .macDev:
      Self.bootstrapOSLogAndFileLog()
      Self.log.debug("configureLogging: OSLog, FileLog")
    case .testing:
      // Skipped on purpose. Tests that need swift-log capture bootstrap a
      // capturing handler themselves; tests that don't get the default
      // stderr handler, which is fine — no test currently relies on log
      // output going to a specific destination.
      break
    }
  }

  private static func bootstrapOSLogAndFileLog(
    extraHandlers: @escaping @Sendable (String) -> [any LogHandler] = { _ in [] }
  ) {
    let sharedState = Container.shared.sharedState()
    LoggingSystem.bootstrap { label in
      MultiplexLogHandler(
        [
          OSLogHandler(label: label),
          FileLogHandler(
            label: label,
            fileURL: AppInfo.logFileURL,
            maxFileSizeBytes: AppInfo.logMaxFileSizeBytes,
            targetFileSizeBytes: AppInfo.logTargetFileSizeBytes,
            // `.inactive` writes stay async; the `.background` transition
            // flushes the queue via AppDelegate.handleScenePhaseChange.
            writeSynchronously: {
              $0 >= .critical || sharedState.$scenePhase.value == .background
            }
          ),
          FileLogHandler(
            label: label,
            fileURL: AppInfo.recentLogFileURL,
            maxFileSizeBytes: AppInfo.recentLogMaxFileSizeBytes,
            targetFileSizeBytes: AppInfo.recentLogTargetFileSizeBytes,
            writeSynchronously: {
              $0 >= .critical || sharedState.$scenePhase.value == .background
            }
          ),
        ]
          + extraHandlers(label)
      )
    }
  }

  // MARK: - Sentry

  // Sentry's configureScope reads UIApplication.applicationState, which is
  // main-thread only; prepareForForeground runs off the main actor.
  @MainActor private static func applySentryEnvironment() {
    SentrySDK.configureScope { scope in
      scope.setEnvironment(AppInfo.environment.rawValue)
    }
  }

  private static func sentryBeforeSendLog(_ log: SentryLog) -> SentryLog? {
    log.setAttribute(
      SentryLog.Attribute(string: AppInfo.environment.rawValue),
      forKey: "sentry.environment"
    )
    return log
  }

  private static func configureSentry() {
    let eventProcessor = Container.shared.sentryEventProcessor()
    SentrySDK.start { options in
      options.dsn =
        "https://df2c739d3207c6cbc8d0e6f965238234@o4508469263663104.ingest.us.sentry.io/4508469264711681"
      options.environment = AppInfo.environment.rawValue
      options.sendDefaultPii = true
      options.enableAppHangTracking = true
      options.enableLogs = true
      options.enableMetricKit = true
      options.enableMetricKitRawPayload = true
      options.beforeSendLog = sentryBeforeSendLog
      options.beforeSend = eventProcessor.process
      options.initialScope = { scope in
        configureInitialSentryScope(scope)
        return scope
      }
    }
  }

  static func configureInitialSentryScope(_ scope: any SentryScopeConfiguring) {
    scope.setTag(value: AppInfo.gitCommitHash, key: "git-commit-hash")
    scope.setUser(Sentry.User(userId: AppInfo.deviceIdentifier))
    scope.addAttachment(
      Sentry.Attachment(
        path: AppInfo.recentLogFileURL.path,
        filename: "recent-log.ndjson",
        contentType: "application/x-ndjson"
      )
    )
    scope.addAttachment(
      Sentry.Attachment(
        path: WidgetInfo.recentLogFileURL.path,
        filename: "recent-widget-log.ndjson",
        contentType: "application/x-ndjson"
      )
    )
  }
}
