// Copyright Justin Bishop, 2025

import AVFoundation
import FactoryKit
import Logging
import Sentry
import SwiftUI

@main
struct PodHavenApp: App {
  @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
  @Environment(\.scenePhase) private var scenePhase

  @InjectedObservable(\.alert) private var alert
  @InjectedObservable(\.sheet) private var sheet
  @DynamicInjected(\.cacheManager) private var cacheManager
  @DynamicInjected(\.notifications) private var notifications
  @DynamicInjected(\.playManager) private var playManager
  @DynamicInjected(\.refreshScheduler) private var refreshScheduler
  @DynamicInjected(\.repo) private var repo
  @DynamicInjected(\.shareService) private var shareService

  @State private var configuringEnvironment = false
  @State private var environmentConfigured = false
  @State private var isStartingServices = false
  @State private var didStartServices = false

  private static let log = Log.as("Main")

  var body: some Scene {
    WindowGroup {
      Group {
        if environmentConfigured {
          ContentView()
            .customAlert($alert.config)
            .customSheet($sheet.config)
        } else {
          ProgressView("Loading...")
        }
      }
      .onChange(of: scenePhase, initial: true) { _, newPhase in
        Task {
          if newPhase == .active {
            await initialize()
            await startServices()
          }

          if didStartServices {
            refreshScheduler.handleScenePhaseChange(to: newPhase)
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
        guard ErrorKit.isRemarkable(error) else { return }
        alert(ErrorKit.coreMessage(for: error))
      }
    } else {
      Self.log.warning("Incoming URL: \(url) is not supported")
      alert("Incoming URL: \(url) is not supported")
    }
  }

  // MARK: - Memory Monitoring

  private func startMemoryWarningMonitoring() {
    guard Function.neverCalled() else { return }

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

  private static func configureLogging() {
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

  private static func configureSentry() {
    SentrySDK.start { options in
      options.dsn =
        "https://df2c739d3207c6cbc8d0e6f965238234@o4508469263663104.ingest.us.sentry.io/4508469264711681"
      options.sendDefaultPii = true
      options.enableAppHangTracking = false
      options.experimental.enableLogs = true
    }
  }

  // MARK: - Launch Handling

  private func initialize() async {
    guard !environmentConfigured else { return }
    guard UIApplication.shared.applicationState == .active else {
      Self.log.debug("environment configuration deferred: app not active")
      return
    }
    guard !configuringEnvironment else {
      Self.log.debug("environment configuration already running")
      return
    }

    configuringEnvironment = true
    defer { configuringEnvironment = false }

    await AppInfo.initializeEnvironment()
    guard !Task.isCancelled else { return }

    Self.configureLogging()
    Self.log.debug("Environment is: \(AppInfo.environment)")
    Self.log.debug("Device identifier is: \(AppInfo.deviceIdentifier)")
    guard !Task.isCancelled else { return }

    environmentConfigured = true
  }

  private func startServices() async {
    guard environmentConfigured else { return }
    guard AppInfo.environment != .testing else { return }
    guard !didStartServices else { return }
    guard !isStartingServices else {
      Self.log.debug("Service startup already running")
      return
    }

    isStartingServices = true
    defer { isStartingServices = false }

    await playManager.start()
    guard !Task.isCancelled else { return }

    await cacheManager.start()
    guard !Task.isCancelled else { return }

    refreshScheduler.start()
    startMemoryWarningMonitoring()

    didStartServices = true
  }
}
