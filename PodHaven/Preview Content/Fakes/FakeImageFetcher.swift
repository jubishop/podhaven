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
    defer { responseCounts[url, default: 0] += 1 }

    if let prefetchedImage = prefetchedImages[url] { return prefetchedImage }

    let handler = fakeHandlers[url, default: defaultHandler]
    let uiImage = try await handler(url)
    try Task.checkCancellation()
    return uiImage
  }

  // MARK: - Response Controls

  private(set) var prefetchCounts: [URL: Int] = [:]
  private(set) var responseCounts: [URL: Int] = [:]

  typealias FetchHandler = @Sendable (URL) async throws -> UIImage
  private var defaultHandler: FetchHandler = { url in return FakeImageFetcher.create(url) }
  private var fakeHandlers: [URL: FetchHandler] = [:]

  func setDefaultHandler(_ handler: @escaping FetchHandler) {
    defaultHandler = handler
  }

  func respond(to url: URL, _ handler: @escaping FetchHandler) {
    fakeHandlers[url] = handler
  }

  func clearCustomHandler(for url: URL) {
    fakeHandlers.removeValue(forKey: url)
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

  @MainActor
  func lazyImage<Content: View>(
    _ url: URL?,
    @ViewBuilder content: @escaping (LazyImageState) -> Content
  ) -> LazyImage<Content> {
    // Check if URL is remote and assert fatal in preview/test contexts
    if let url = url, !url.isFileURL {
      Assert.fatal(
        """
        ❌ FATAL: Attempted remote image loading in preview/test context!
        URL: \(url)
        Use local file URLs from Preview Assets or nil for grey boxes instead.
        """
      )
    }

    return LazyImage(url: url, content: content)
  }
}
#endif
