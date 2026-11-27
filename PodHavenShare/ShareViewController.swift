// Copyright Justin Bishop, 2025

import OSLog
import UIKit
import UniformTypeIdentifiers

class ShareViewController: UIViewController {
  private let log = Logger(subsystem: "PodHavenShare", category: "viewController")

  override func viewDidLoad() {
    log.debug("viewDidLoad called")
    super.viewDidLoad()
  }

  override func viewDidAppear(_ animated: Bool) {
    log.debug("viewDidAppear called")
    super.viewDidAppear(animated)

    guard let extensionContext else {
      log.error("Share request has no extension context")
      return
    }

    Task { [weak self, extensionContext] in
      guard let self else { return }
      do {
        let application = try findUIApplication()
        try await ShareLauncher.execute(from: application, with: extensionContext)
      } catch {
        log.error("Share execution failed: \(error, privacy: .public)")
        extensionContext.cancelRequest(withError: error)
        return
      }

      extensionContext.completeRequest(returningItems: nil, completionHandler: nil)
    }
  }

  private func findUIApplication() throws -> UIApplication {
    var responder: UIResponder? = self
    while responder != nil {
      if let application = responder as? UIApplication {
        return application
      }
      responder = responder?.next
    }
    throw ShareExtensionError.applicationNotFound
  }
}
