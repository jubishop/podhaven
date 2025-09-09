// Copyright Justin Bishop, 2025

import FactoryKit
import Foundation
import Nuke
import NukeUI
import SwiftUI

extension Container {
  var imageFetcher: Factory<any ImageFetchable> {
    Factory(self) { ImageFetcher() }.scope(.cached)
  }
}

struct ImageFetcher: ImageFetchable {
  private static let log = Log.as("ImageFetcher")

  private let pipeline = ImagePipeline.shared
  private let prefetcher = ImagePrefetcher()

  fileprivate init() {}

  func prefetch(_ urls: [URL]) async {
    Self.log.debug("prefetching: \(urls)")

    prefetcher.startPrefetching(with: urls)
  }

  func fetch(_ url: URL) async throws -> UIImage {
    try await pipeline.image(for: url)
  }

  @MainActor
  func lazyImage<Content: View>(
    _ url: URL?,
    @ViewBuilder content: @escaping (LazyImageState) -> Content
  ) -> LazyImage<Content> {
    LazyImage(url: url, content: content)
  }
}
