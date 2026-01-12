// Copyright Justin Bishop, 2025

import Foundation
import UIKit

@MainActor protocol ApplicationProviding: Sendable {
  var applicationState: UIApplication.State { get }

  func beginBackgroundTask(
    withName taskName: String?,
    expirationHandler handler: (@MainActor @Sendable () -> Void)?
  ) -> UIBackgroundTaskIdentifier

  func endBackgroundTask(_ identifier: UIBackgroundTaskIdentifier)

  func open(
    _ url: URL,
    options: [UIApplication.OpenExternalURLOptionsKey: Any],
    completionHandler completion: (@MainActor @Sendable (Bool) -> Void)?
  )
}

extension ApplicationProviding {
  func open(_ url: URL) {
    open(url, options: [:], completionHandler: nil)
  }
}
