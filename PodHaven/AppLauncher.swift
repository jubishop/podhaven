// Copyright Justin Bishop, 2026

import AVFoundation
import FactoryKit
import Intents
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
  @DynamicInjected(\.playManager) private var playManager
  @DynamicInjected(\.processActivationDiagnostics) private var processActivationDiagnostics
  @DynamicInjected(\.recommendationEngine) private var recommendationEngine
  @DynamicInjected(\.refreshScheduler) private var refreshScheduler
  @DynamicInjected(\.stateManager) private var stateManager
  @DynamicInjected(\.thermalPressureMonitor) private var thermalPressureMonitor
  @DynamicInjected(\.transcriptionAvailability) private var transcriptionAvailability
  @DynamicInjected(\.widgetSnapshotWriter) private var widgetSnapshotWriter

  private var taskPriority: @Sendable (TaskPriority?) -> TaskPriority? {
    Container.shared.taskPriority()
  }
  private var userNotificationManager: UserNotificationManager {
    Container.shared.userNotificationManager()
  }

  private static let log = Log.as("AppLauncher")
  private let prepareForPlaybackOnce = AsyncOnce()
  private let prepareForForegroundOnce = AsyncOnce()

  // MXMetricManager holds subscribers weakly, so this must outlive registration.
  private let metricKitMonitor = MetricKitMonitor()

  fileprivate init() {}

  // MARK: - Bootstrap

  @MainActor func bootstrap() {
    AppInfo.initializeEnvironment()
    guard AppInfo.environment != .preview else { return }

    configureLogging()
    Self.removeRetiredChartDiagnostics()
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
    processActivationDiagnostics.recordLaunch(
      applicationState: UIApplication.shared.applicationState,
      prewarmed: ProcessInfo.processInfo.environment["ActivePrewarm"] == "1"
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
    Container.shared.silenceProcessor().register()
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

  // MARK: - Shared Data

  func prepareForBrowsing() {
    stateManager.start()
  }

  // MARK: - Playback

  func prepareForPlayback() async {
    await prepareForPlaybackOnce.run {
      Self.log.info("Preparing for background audio playback")
      await self.measureStartup("stateManager") { self.prepareForBrowsing() }
      await self.measureStartup("playManager") { await self.playManager.start() }
      await self.measureStartup("widgetSnapshotWriter") { self.widgetSnapshotWriter.start() }
    }
  }

  // MARK: - Foreground

  func prepareForForeground() async {
    await prepareForForegroundOnce.run {
      Self.log.info("Preparing for foreground")
      let operation = Log.Operation(Self.log, kind: "startup.foreground")

      await AppInfo.finalizeEnvironment()
      await Self.applySentryEnvironment()
      guard AppInfo.environment != .testing else { return }
      guard !Task.isCancelled else { return }

      let transcriptionAvailability = self.transcriptionAvailability
      Task(priority: self.taskPriority(.utility)) {
        await transcriptionAvailability.prepare()
      }

      await self.measureStartup("userNotificationManager") {
        await self.userNotificationManager.initialize()
      }
      if INPreferences.siriAuthorizationStatus() == .notDetermined {
        INPreferences.requestSiriAuthorization { status in
          Self.log.info("Siri authorization status: \(status.rawValue)")
        }
      }
      guard !Task.isCancelled else { return }

      Self.log.debug("Device identifier is: \(AppInfo.deviceIdentifier)")
      Self.log.debug("My device?: \(AppInfo.myDevice)")
      Self.log.debug("Final environment is: \(AppInfo.environment)")
      Self.log.debug("Build version: \(AppInfo.version) (\(AppInfo.buildNumber))")
      Self.log.debug("Git commit hash is: \(AppInfo.gitCommitHash)")

      // No-op if an intent already triggered prepareForPlayback during the cold launch.
      await self.prepareForPlayback()
      guard !Task.isCancelled else { return }

      await self.measureStartup("cacheManager") { self.cacheManager.start() }
      await self.measureStartup("recommendationEngine") { self.recommendationEngine.start() }
      await self.measureStartup("memoryWarningMonitor") {
        await Container.shared.memoryWarningMonitor().start()
      }
      operation.record(.completed)
    }

    guard AppInfo.environment != .testing else { return }
    guard !Task.isCancelled else { return }
    await playManager.restorePersistedEpisodeForForeground()
  }

  private func measureStartup<Result>(
    _ step: String,
    file: String = #fileID,
    function: String = #function,
    line: UInt = #line,
    _ work: () async -> Result
  ) async -> Result {
    let operation = Log.Operation(
      Self.log,
      kind: "startup.\(step)",
      file: file,
      function: function,
      line: line
    )
    let result = await work()
    operation.record(.completed)
    return result
  }

  // MARK: - Logging

  private func configureLogging() {
    switch AppInfo.environment {
    case .deployed, .appStore, .testFlight:
      Self.bootstrapOSLogAndFileLog { label in
        [SentryLogHandler(label: label), CrashReportHandler(label: label)]
      }
      Self.log.debug("configureLogging: starting diagnostic session")
      FileLogHandler.flush()
      Self.configureSentry()
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

  private static func removeRetiredChartDiagnostics() {
    let logDirectory = AppInfo.recentLogFileURL.deletingLastPathComponent()
    for url in [
      logDirectory.appendingPathComponent("chart-progress", isDirectory: true),
      logDirectory.appendingPathComponent("chart-progress.ndjson"),
    ] {
      do {
        try Container.shared.fileManager().removeItem(at: url)
        log.info("Removed retired chart diagnostics at \(url.lastPathComponent)")
      } catch {
        guard !ErrorKit.isMissingFile(error) else { continue }
        log.caughtError("Could not remove retired chart diagnostics", error)
      }
    }
  }

  private static func bootstrapOSLogAndFileLog(
    extraHandlers: @escaping @Sendable (String) -> [any LogHandler] = { _ in [] }
  ) {
    LoggingSystem.bootstrap { label in
      MultiplexLogHandler(
        [OSLogHandler(label: label)] + fileLogHandlers(label: label) + extraHandlers(label)
      )
    }
  }

  static func fileLogHandlers(label: String) -> [any LogHandler] {
    [
      FileLogHandler(
        label: label,
        fileURL: AppInfo.logFileURL,
        maxFileSizeBytes: AppInfo.logMaxFileSizeBytes,
        targetFileSizeBytes: AppInfo.logTargetFileSizeBytes,
        writeSynchronously: { $0 >= .critical }
      ),
      FileLogHandler(
        label: label,
        fileURL: AppInfo.recentLogFileURL,
        maxFileSizeBytes: AppInfo.recentLogMaxFileSizeBytes,
        targetFileSizeBytes: AppInfo.recentLogTargetFileSizeBytes,
        historyPolicy: .preservePreviousSession,
        writeSynchronously: { $0 >= .critical }
      ),
    ]
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
    SentrySDK.start { options in
      configureSentryOptions(options)
    }
    Container.shared.appHangReportingGate().start()
    Task { await Container.shared.siriResolutionDiagnostics().captureExtensionFailures() }
  }

  @diagnose(
    DeprecatedDeclaration,
    as: warning,
    reason: "Sentry attachment hints await the next major SDK callback"
  )
  static func configureSentryOptions(_ options: Sentry.Options) {
    let eventProcessor = Container.shared.sentryEventProcessor()
    options.dsn =
      "https://df2c739d3207c6cbc8d0e6f965238234@o4508469263663104.ingest.us.sentry.io/4508469264711681"
    options.environment = AppInfo.environment.rawValue
    options.sendDefaultPii = true
    options.enableCaptureFailedRequests = false
    options.enableAppHangTracking = true
    options.enableLogs = true
    options.enableMetricKit = true
    options.enableMetricKitRawPayload = true
    options.beforeSendLog = sentryBeforeSendLog
    options.beforeSendWithHint = { event, hint in
      guard let event = eventProcessor.process(event) else { return nil }
      let attachments =
        recentLogAttachments + Container.shared.siriResolutionDiagnostics().attachments()
      for attachment in attachments
      where !hint.attachments.contains(where: { $0.filename == attachment.filename }) {
        hint.attachments.append(attachment)
      }
      return event
    }
    options.initialScope = { scope in
      configureInitialSentryScope(scope)
      return scope
    }
  }

  static func configureInitialSentryScope(_ scope: any SentryScopeConfiguring) {
    scope.setTag(value: AppInfo.gitCommitHash, key: "git-commit-hash")
    scope.setTag(value: FileLogHandler.sessionID, key: "log-session-id")
    scope.setUser(Sentry.User(userId: AppInfo.deviceIdentifier))
    for attachment in recentLogAttachments {
      scope.addAttachment(attachment)
    }
  }

  private static var recentLogAttachments: [Sentry.Attachment] {
    [
      Sentry.Attachment(
        path: AppInfo.recentLogFileURL.path,
        filename: "recent-log.ndjson",
        contentType: "application/x-ndjson"
      ),
      Sentry.Attachment(
        path: WidgetInfo.recentLogFileURL.path,
        filename: "recent-widget-log.ndjson",
        contentType: "application/x-ndjson"
      ),
    ]
  }
}
