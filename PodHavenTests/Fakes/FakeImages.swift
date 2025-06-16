// Copyright Justin Bishop, 2025

import Foundation
import Nuke
import SwiftUI

@testable import PodHaven

actor FakeImages: ImageFetchable {
  nonisolated func prefetch(_ urls: [URL]) {}

  typealias FetchHandler = @Sendable (URL) async throws -> UIImage

  private(set) var responseCounts: [URL: Int] = [:]

  private var defaultHandler: FetchHandler = { url in return FakeImages.create(url) }
  private var fakeHandlers: [URL: FetchHandler] = [:]

  func setDefaultResponse(_ handler: @escaping FetchHandler) {
    defaultHandler = handler
  }

  func respond(to url: URL, _ handler: @escaping FetchHandler) {
    fakeHandlers[url] = handler
  }

  func clearCustomHandler(for url: URL) {
    fakeHandlers.removeValue(forKey: url)
  }

  func fetchImage(_ url: URL) async throws -> UIImage {
    defer { responseCounts[url, default: 0] += 1 }

    let handler = fakeHandlers[url, default: defaultHandler]
    let uiImage = try await handler(url)
    try Task.checkCancellation()
    return uiImage
  }

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
