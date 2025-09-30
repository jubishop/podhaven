// Copyright Justin Bishop, 2025

import FactoryKit
import UIKit

// MARK: - AppDelegate

final class AppDelegate: NSObject, UIApplicationDelegate {
  @DynamicInjected(\.cacheBackgroundDelegate) private var cacheBackgroundDelegate
  @DynamicInjected(\.cachePurger) private var cachePurger
  @DynamicInjected(\.refreshScheduler) private var refreshScheduler

  func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
  ) -> Bool {
    refreshScheduler.register()
    cachePurger.register()

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
}
