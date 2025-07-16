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

    guard let application = try? findUIApplication()
    else {
      log.error("Failed to find UIApplication")
      extensionContext.completeRequest(returningItems: nil, completionHandler: nil)
      return
    }

    Task {
      do {
        try await ShareLauncher.execute(from: application, with: extensionContext)
      } catch {
        log.error("Share execution failed: \(error)")
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
