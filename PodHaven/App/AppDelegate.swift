// Copyright Justin Bishop, 2025

import UIKit

// MARK: - AppDelegate

final class AppDelegate: NSObject, UIApplicationDelegate {
  func application(
    _ application: UIApplication,
    handleEventsForBackgroundURLSession identifier: String,
    completionHandler: @escaping () -> Void
  ) {
    BackgroundURLSessionCompletionCenter.shared.store(
      identifier: identifier,
      completion: completionHandler
    )
  }
}
