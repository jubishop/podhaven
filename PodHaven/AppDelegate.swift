// Copyright Justin Bishop, 2025

import FactoryKit
import UIKit

// MARK: - AppDelegate

final class AppDelegate: NSObject, UIApplicationDelegate {
  @DynamicInjected(\.cacheBackgroundDelegate) private var cacheBackgroundDelegate

  func application(
    _ application: UIApplication,
    handleEventsForBackgroundURLSession identifier: String,
    completionHandler: @escaping () -> Void
  ) {
    Task {
      await cacheBackgroundDelegate.store(
        identifier: identifier,
        completion: completionHandler
      )
    }
  }
}
