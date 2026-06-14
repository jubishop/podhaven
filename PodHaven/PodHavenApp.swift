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
  @DynamicInjected(\.bgTaskScheduler) private var bgTaskScheduler
  @DynamicInjected(\.cachePurger) private var cachePurger
  @DynamicInjected(\.databaseMaintainer) private var databaseMaintainer
  @DynamicInjected(\.embeddingProcessor) private var embeddingProcessor
  @DynamicInjected(\.transcriptionProcessor) private var transcriptionProcessor
  @DynamicInjected(\.recommendationEngine) private var recommendationEngine
  @DynamicInjected(\.refreshScheduler) private var refreshScheduler
  @DynamicInjected(\.sharedState) private var sharedState
  @DynamicInjected(\.notificationService) private var notificationService
  @DynamicInjected(\.shareService) private var shareService
  @DynamicInjected(\.userNotificationManager) private var userNotificationManager
  @DynamicInjected(\.userSettings) private var userSettings
  @DynamicInjected(\.widgetService) private var widgetService

  @State private var initialized = false

  nonisolated private static let log = Log.as("Main")

  var body: some Scene {
    WindowGroup {
      Group {
        if initialized {
          ContentView()
            .customAlert($alert.config, isEnabled: sheet.config == nil)
            .customSheet($sheet.config, alert: $alert.config)
        } else {
          ProgressView("Loading...")
        }
      }
      .preferredColorScheme(userSettings.appearanceMode.colorScheme)
      .onChange(of: scenePhase, initial: true) { _, newPhase in
        sharedState.$scenePhase.new(newPhase)

        switch newPhase {
        case .active:
          Task {
            await appLauncher.prepareForForeground()
            initialized = true
            // Skip the notify if the phase changed during the await: the
            // captured `.active` would be stale (the gate would re-enter
            // foreground while backgrounded), and the `.background` arm
            // already sync-notified when the transition happened.
            guard sharedState.$scenePhase.value == .active else { return }
            notifyScenePhaseChange(.active)
          }
        case .background:
          notifyScenePhaseChange(newPhase)
          if initialized {
            bgTaskScheduler.getPendingTaskRequests { requests in
              if requests.isEmpty {
                Self.log.error("No pending background tasks after entering background")
              } else {
                Self.log.debug(
                  """
                  Pending background tasks:
                  \(BackgroundTaskScheduler.formatPendingTasks(requests))
                  """
                )
              }
            }
          }
        default:
          break
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

  // MARK: - Scene Phase

  private func notifyScenePhaseChange(_ phase: ScenePhase) {
    appDelegate.handleScenePhaseChange(to: phase)
    refreshScheduler.handleScenePhaseChange(to: phase)
    cachePurger.handleScenePhaseChange(to: phase)
    databaseMaintainer.handleScenePhaseChange(to: phase)
    embeddingProcessor.handleScenePhaseChange(to: phase)
    transcriptionProcessor.handleScenePhaseChange(to: phase)
    recommendationEngine.handleScenePhaseChange(to: phase)
    Task { await userNotificationManager.handleScenePhaseChange(to: phase) }
  }

  // MARK: - URL Handling

  private func handleIncomingURL(_ url: URL) async {
    if ShareService.isShareURL(url) {
      do {
        try await shareService.handleIncomingURL(url)
      } catch {
        Self.log.caughtError("handleIncomingURL: failed for share URL \(url)", error)
        guard ErrorKit.isRemarkable(error) else { return }
        alert(ErrorKit.message(for: error))
      }
    } else if WidgetService.isWidgetURL(url) {
      await widgetService.handleIncomingURL(url)
    } else if NotificationService.isNotificationURL(url) {
      await notificationService.handleIncomingURL(url)
    } else {
      Self.log.warning("Incoming URL: \(url) is not supported")
      alert("Incoming URL: \(url) is not supported")
    }
  }
}
