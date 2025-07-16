// Copyright Justin Bishop, 2025

import Foundation
import OSLog
import UIKit
import UniformTypeIdentifiers

enum ShareLauncher {
  private static let log = Logger(subsystem: "PodHavenShare", category: "ShareLauncher")

  static func execute(
    from application: UIApplication,
    with extensionContext: NSExtensionContext
  ) async throws {
    guard let inputItems = extensionContext.inputItems as? [NSExtensionItem]
    else { throw ShareExtensionError.noInputItems }

    for inputItem in inputItems {
      guard let attachments = inputItem.attachments else { continue }

      for attachment in attachments {
        if attachment.hasItemConformingToTypeIdentifier(UTType.url.identifier) {
          let url: URL = try await withCheckedThrowingContinuation { continuation in
            attachment.loadItem(forTypeIdentifier: UTType.url.identifier, options: nil) {
              item,
              error in

              if let error = error {
                continuation.resume(throwing: ShareExtensionError.urlLoadingFailed(error))
                return
              }

              guard let url = item as? URL
              else {
                continuation.resume(throwing: ShareExtensionError.itemNotURL)
                return
              }

              continuation.resume(returning: url)
            }
          }

          log.info("Shared URL: \(url.absoluteString, privacy: .public)")
          try launchPodHaven(from: application, with: url)
          return
        }
      }
    }

    throw ShareExtensionError.noURLFound
  }

  private static func launchPodHaven(from application: UIApplication, with url: URL) throws {
    var components = URLComponents()
    components.scheme = "podhaven"
    components.host = "share"
    components.queryItems = [URLQueryItem(name: "url", value: url.absoluteString)]

    guard let podhavenURL = components.url
    else { throw ShareExtensionError.invalidURLScheme }

    log.info("Launching PodHaven with URL: \(podhavenURL.absoluteString, privacy: .public)")

    application.open(podhavenURL) { success in
      log.info("Launch result: \(success)")
    }
  }
}
