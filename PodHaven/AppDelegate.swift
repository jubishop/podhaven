// Copyright Justin Bishop, 2025

import FactoryKit
import Logging
import SwiftUI
import Tagged
import UIKit
import UserNotifications

// MARK: - AppDelegate

final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
  @DynamicInjected(\.appLauncher) private var appLauncher
  @DynamicInjected(\.cacheBackgroundDelegate) private var cacheBackgroundDelegate
  @DynamicInjected(\.notificationService) private var notificationService

  private static let log = Log.as("AppDelegate")

  func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
  ) -> Bool {
    UNUserNotificationCenter.current().delegate = self
    appLauncher.bootstrap()
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

  // MARK: - Scene Phase

  func handleScenePhaseChange(to phase: ScenePhase) {
    if phase == .background {
      FileLogHandler.flush()
    }
  }

  // MARK: - UNUserNotificationCenterDelegate

  func userNotificationCenter(
    _ center: UNUserNotificationCenter,
    willPresent notification: UNNotification
  ) async -> UNNotificationPresentationOptions {
    [.banner, .sound]
  }

  func userNotificationCenter(
    _ center: UNUserNotificationCenter,
    didReceive response: UNNotificationResponse
  ) async {
    let userInfo = response.notification.request.content.userInfo

    guard let urlString = userInfo["url"] as? String,
      let url = URL(string: urlString)
    else {
      Self.log.warning("Notification tap: no valid URL in userInfo")
      Container.shared.navigation().showPodcastList(.subscribed)
      return
    }

    Self.log.debug("Notification tap: \(url)")
    await notificationService.handleIncomingURL(url)
  }
}
