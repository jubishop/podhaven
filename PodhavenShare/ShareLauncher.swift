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
        // Handle file URL attachments
        if attachment.hasItemConformingToTypeIdentifier("public.file-url") {
          let sourceURL = try await loadURL(from: attachment, typeIdentifier: "public.file-url")
          log.debug("Shared file URL: \(sourceURL, privacy: .public)")
          let shareURL = try await copyFileToSharedContainer(sourceURL)
          try await launchPodHaven(from: application, with: shareURL)
          return
        }

        // Handle http URL attachments
        if attachment.hasItemConformingToTypeIdentifier(UTType.url.identifier) {
          let url = try await loadURL(from: attachment, typeIdentifier: UTType.url.identifier)
          log.debug("Shared URL: \(url, privacy: .public)")
          try await launchPodHaven(from: application, with: url)
          return
        }
      }
    }

    throw ShareExtensionError.noURLFound
  }

  private static func loadURL(from attachment: NSItemProvider, typeIdentifier: String) async throws
    -> URL
  {
    try await withCheckedThrowingContinuation { continuation in
      attachment.loadItem(forTypeIdentifier: typeIdentifier, options: nil) { item, error in
        if let error = error {
          continuation.resume(throwing: ShareExtensionError.urlLoadingFailed(error))
          return
        }

        guard let url = item as? URL else {
          continuation.resume(throwing: ShareExtensionError.itemNotURL)
          return
        }

        continuation.resume(returning: url)
      }
    }
  }

  private static func copyFileToSharedContainer(_ sourceURL: URL) async throws -> URL {
    guard
      let sharedContainer = FileManager.default.containerURL(
        forSecurityApplicationGroupIdentifier: "group.podhaven.shared"
      )
    else { throw ShareExtensionError.sharedContainerNotFound }

    let fileExtension = sourceURL.pathExtension
    let filename = "shared_file_\(UUID().uuidString).\(fileExtension)"
    let shareURL = sharedContainer.appendingPathComponent(filename)

    let data = try Data(contentsOf: sourceURL)
    try data.write(to: shareURL)

    log.debug("Successfully copied file to shared container: \(shareURL, privacy: .public)")
    return shareURL
  }

  private static func launchPodHaven(from application: UIApplication, with url: URL) async throws {
    var components = URLComponents()
    components.scheme = "podhaven"
    components.host = "share"
    components.queryItems = [URLQueryItem(name: "url", value: url.absoluteString)]

    guard let podhavenURL = components.url
    else { throw ShareExtensionError.invalidURLScheme }

    log.info("Launching PodHaven with URL: \(podhavenURL, privacy: .public)")

    await application.open(podhavenURL) { success in
      log.debug("Launch result: \(success)")
    }
  }
}
