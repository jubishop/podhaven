// Copyright Justin Bishop, 2025

import AVFoundation
import FactoryKit
import Logging
import SwiftUI

@main
struct PodHavenApp: App {
  @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
  @Environment(\.scenePhase) private var scenePhase

  @InjectedObservable(\.alert) private var alert
  @InjectedObservable(\.sheet) private var sheet
  @DynamicInjected(\.cacheManager) private var cacheManager
  @DynamicInjected(\.cachePurger) private var cachePurger
  @DynamicInjected(\.fileLogManager) private var fileLogManager
  @DynamicInjected(\.notifications) private var notifications
  @DynamicInjected(\.playManager) private var playManager
  @DynamicInjected(\.refreshScheduler) private var refreshScheduler
  @DynamicInjected(\.repo) private var repo
  @DynamicInjected(\.sharedState) private var sharedState
  @DynamicInjected(\.shareService) private var shareService
  @DynamicInjected(\.stateManager) private var stateManager
  @DynamicInjected(\.userNotificationManager) private var userNotificationManager
  @DynamicInjected(\.userSettings) private var userSettings

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
      .preferredColorScheme(userSettings.appearanceMode.colorScheme)
      .onChange(of: scenePhase, initial: true) { _, newPhase in
        Task {
          if newPhase == .active {
            await initialize()
            await startServices()
          }

          if didStartServices {
            fileLogManager.handleScenePhaseChange(to: newPhase)
            refreshScheduler.handleScenePhaseChange(to: newPhase)
            cachePurger.handleScenePhaseChange(to: newPhase)
            await userNotificationManager.handleScenePhaseChange(to: newPhase)
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

  // MARK: - Launch Handling

  private func initialize() async {
    guard !environmentConfigured else { return }
    guard UIApplication.shared.applicationState == .active else {
      Self.log.debug("Environment configuration deferred: app not active")
      return
    }
    guard !configuringEnvironment else {
      Self.log.debug("Environment configuration already running")
      return
    }

    configuringEnvironment = true
    defer { configuringEnvironment = false }

    // Initial environment and logging already configured in AppDelegate
    await AppInfo.finalizeEnvironment()
    await userNotificationManager.initialize()
    guard !Task.isCancelled else { return }

    Self.log.debug("Device identifier is: \(AppInfo.deviceIdentifier)")
    Self.log.debug("Final environment is: \(AppInfo.environment)")
    Self.log.debug("Build version: \(AppInfo.version) (\(AppInfo.buildNumber))")

    stateManager.start()
    environmentConfigured = true
  }

  private func startServices() async {
    guard environmentConfigured else { return }
    guard AppInfo.environment != .testing else { return }

    guard !didStartServices else { return }
    guard UIApplication.shared.applicationState == .active else {
      Self.log.debug("Service startup deferred: app not active")
      return
    }
    guard !isStartingServices else {
      Self.log.debug("Service startup already running")
      return
    }

    isStartingServices = true
    defer { isStartingServices = false }

    startMemoryWarningMonitoring()

    await playManager.start()
    guard !Task.isCancelled else { return }

    cacheManager.start()
    guard !Task.isCancelled else { return }

    refreshScheduler.start()
    cachePurger.start()

    didStartServices = true
  }
}
