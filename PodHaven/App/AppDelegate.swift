// Copyright Justin Bishop, 2025

import FactoryKit
import UIKit

// MARK: - AppDelegate

final class AppDelegate: NSObject, UIApplicationDelegate {
  func application(
    _ application: UIApplication,
    handleEventsForBackgroundURLSession identifier: String,
    completionHandler: @escaping () -> Void
  ) {
    Container.shared.backgroundURLSessionCompletionCenter()
      .store(
        identifier: identifier,
        completion: completionHandler
      )
  }
}
