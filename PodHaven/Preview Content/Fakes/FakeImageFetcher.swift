#if DEBUG
// Copyright Justin Bishop, 2025

import Foundation
import Nuke
import NukeUI
import SwiftUI

actor FakeImageFetcher: ImageFetchable {
  // MARK: - ImageFetchable

  private var prefetchedImages: [URL: UIImage] = [:]

  func prefetch(_ urls: [URL]) async {
    for url in urls {
      prefetchCounts[url, default: 0] += 1
      prefetchedImages[url] = try? await fetch(url)
    }
  }

  func fetch(_ url: URL) async throws -> UIImage {
    if let prefetchedImage = prefetchedImages[url] { return prefetchedImage }

    let handler = fakeHandlers[url, default: defaultHandler]
    let uiImage = try await handler(url)
    try Task.checkCancellation()
    return uiImage
  }

  // MARK: - Response Controls

  private(set) var prefetchCounts: [URL: Int] = [:]

  typealias FetchHandler = @Sendable (URL) async throws -> UIImage
  private var defaultHandler: FetchHandler = { url in return FakeImageFetcher.create(url) }
  private var fakeHandlers: [URL: FetchHandler] = [:]

  func setDefaultHandler(_ handler: @escaping FetchHandler) {
    defaultHandler = handler
  }

  func clearCustomHandler(for url: URL) {
    fakeHandlers.removeValue(forKey: url)
  }

  func respond(to url: URL, _ handler: @escaping FetchHandler) {
    fakeHandlers[url] = handler
  }

  func respond(to url: URL, uiImage: UIImage) {
    respond(to: url) { url in uiImage }
  }

  func respond(to url: URL, error: Error) {
    respond(to: url) { _ in throw error }
  }

  // MARK: - Creation Helpers

  static func create(_ url: URL) -> UIImage {
    let hash = abs(url.absoluteString.hashValue)
    let size = CGSize(width: 100, height: 100)
    let color = UIColor(
      red: CGFloat((hash >> 16) & 0xFF) / 255.0,
      green: CGFloat((hash >> 8) & 0xFF) / 255.0,
      blue: CGFloat(hash & 0xFF) / 255.0,
      alpha: 1.0
    )

    return UIGraphicsImageRenderer(size: size)
      .image { context in
        color.setFill()
        context.fill(CGRect(origin: .zero, size: size))
      }
  }
}

#endif
