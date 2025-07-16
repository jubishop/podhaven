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
    super.viewDidAppear(animated)
    log.debug("viewDidAppear called")

    guard let extensionContext = extensionContext
    else { fatalError("extensionContext is nil") }

    guard let inputItems = extensionContext.inputItems as? [NSExtensionItem] else {
      log.error("No input items found")
      extensionContext.completeRequest(returningItems: nil, completionHandler: nil)
      return
    }

    for inputItem in inputItems {
      guard let attachments = inputItem.attachments else { continue }

      for attachment in attachments {
        if attachment.hasItemConformingToTypeIdentifier(UTType.url.identifier) {
          attachment.loadItem(forTypeIdentifier: UTType.url.identifier, options: nil) {
            item,
            error in
            if let error = error {
              self.log.error("Error loading URL: \(error)")
              extensionContext.completeRequest(returningItems: nil, completionHandler: nil)
              return
            }

            guard let url = item as? URL else {
              self.log.error("Item is not a URL")
              extensionContext.completeRequest(returningItems: nil, completionHandler: nil)
              return
            }

            self.launchPodHaven(with: url, using: extensionContext)
          }
          return
        }
      }
    }

    log.error("No URL found in shared content")
    extensionContext.completeRequest(returningItems: nil, completionHandler: nil)
  }

  private func launchPodHaven(with url: URL, using extensionContext: NSExtensionContext) {
    var components = URLComponents()
    components.scheme = "podhaven"
    components.host = "share"
    components.queryItems = [URLQueryItem(name: "url", value: url.absoluteString)]

    guard let podhavenURL = components.url else {
      log.error("Failed to create PodHaven URL scheme")
      extensionContext.completeRequest(returningItems: nil, completionHandler: nil)
      return
    }

    log.info("Launching PodHaven with URL: \(podhavenURL.absoluteString, privacy: .public)")
    log.info("Original shared URL: \(url.absoluteString, privacy: .public)")

    // Try responder chain approach
    var responder: UIResponder? = self
    while responder != nil {
      if let application = responder as? UIApplication {
        application.open(podhavenURL) { success in
          self.log.info("Launch result: \(success)")
          extensionContext.completeRequest(returningItems: nil, completionHandler: nil)
        }
        return
      }
      responder = responder?.next
    }

    // Fallback if responder chain doesn't work
    log.warning("Could not find UIApplication in responder chain")
    extensionContext.completeRequest(returningItems: nil, completionHandler: nil)
  }
}
