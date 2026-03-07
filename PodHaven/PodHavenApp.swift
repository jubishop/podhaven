// Copyright Justin Bishop, 2025

import FactoryKit
import Logging
import SwiftUI

@main
struct PodHavenApp: App {
  @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
  @Environment(\.scenePhase) private var scenePhase

  @InjectedObservable(\.alert) private var alert
  @InjectedObservable(\.sheet) private var sheet
  @DynamicInjected(\.appLauncher) private var appLauncher
  @DynamicInjected(\.cachePurger) private var cachePurger
  @DynamicInjected(\.refreshScheduler) private var refreshScheduler
  @DynamicInjected(\.sharedState) private var sharedState
  @DynamicInjected(\.shareService) private var shareService
  @DynamicInjected(\.userNotificationManager) private var userNotificationManager
  @DynamicInjected(\.userSettings) private var userSettings

  @State private var initialized = false

  private static let log = Log.as("Main")

  var body: some Scene {
    WindowGroup {
      Group {
        if initialized {
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
          }

          sharedState.$isActive.new(newPhase == .active)
          if initialized {
            appDelegate.handleScenePhaseChange(to: newPhase)
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

  // MARK: - Launch Handling

  private func initialize() async {
    guard !initialized else { return }
    guard UIApplication.shared.applicationState == .active else {
      Self.log.debug("Initialization deferred: app not active")
      return
    }

    await appLauncher.prepareForForeground()
    guard !Task.isCancelled else { return }

    initialized = true
  }
}
