// Copyright Justin Bishop, 2025

import OSLog
import UIKit

class ShareViewController: UIViewController {
  private let log = Logger(subsystem: "PodHaven", category: "Share")

  override func viewDidLoad() {
    super.viewDidLoad()
    processSharedContent()
  }

  private func processSharedContent() {
    guard let extensionContext = extensionContext,
      let inputItems = extensionContext.inputItems as? [NSExtensionItem]
    else {
      log.error("No input items found")
      completeRequest()
      return
    }

    for inputItem in inputItems {
      guard let attachments = inputItem.attachments else { continue }

      for attachment in attachments {
        if attachment.hasItemConformingToTypeIdentifier("public.url") {
          attachment.loadItem(forTypeIdentifier: "public.url", options: nil) {
            [weak self] item, error in
            DispatchQueue.main.async {
              if let error = error {
                self?.log.error("Error loading URL: \(error.localizedDescription)")
                self?.completeRequest()
                return
              }

              guard let url = item as? URL else {
                self?.log.error("Item is not a URL")
                self?.completeRequest()
                return
              }

              self?.launchPodHaven(with: url)
            }
          }
          return
        }
      }
    }

    log.error("No URL found in shared content")
    completeRequest()
  }

  private func launchPodHaven(with url: URL) {
    guard
      let podhavenURL = URL(
        string:
          "podhaven://share?url=\(url.absoluteString.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "")"
      )
    else {
      log.error("Failed to create PodHaven URL scheme")
      completeRequest()
      return
    }

    log.info("Launching PodHaven with URL: \(url.absoluteString, privacy: .public)")

    var responder: UIResponder? = self
    while responder != nil {
      if let application = responder as? UIApplication {
        application.open(podhavenURL) { [weak self] success in
          DispatchQueue.main.async {
            if success {
              self?.log.info("Successfully launched PodHaven")
            } else {
              self?.log.error("Failed to launch PodHaven")
            }
            self?.completeRequest()
          }
        }
        return
      }
      responder = responder?.next
    }

    completeRequest()
  }

  private func completeRequest() {
    extensionContext?.completeRequest(returningItems: nil, completionHandler: nil)
  }
}
