// Copyright Justin Bishop, 2025

import OSLog
import UIKit
import UniformTypeIdentifiers

class ShareViewController: UIViewController {
  private let log = Logger(subsystem: "PodHavenShare", category: "main")

  override func viewDidLoad() {
    log.debug("viewDidLoad called")
    super.viewDidLoad()
  }

  override func viewDidAppear(_ animated: Bool) {
    log.debug("viewDidAppear called")
    super.viewDidAppear(animated)

    guard let extensionContext = extensionContext
    else { fatalError("extensionContext is nil") }

    Task {
      do {
        try await ShareLauncher.execute(using: extensionContext, from: self)
      } catch {
        log.error("Share execution failed: \(error)")
      }

      extensionContext.completeRequest(returningItems: nil, completionHandler: nil)
    }
  }
}
