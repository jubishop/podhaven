// Copyright Justin Bishop, 2025

import FactoryKit
import Foundation
import Nuke
import SwiftUI

extension Container {
  var imageFetcher: Factory<any ImageFetchable> {
    Factory(self) { ImageFetcher() }.scope(.cached)
  }
}

struct ImageFetcher: ImageFetchable {
  private let log = Log.as("ImageFetcher")

  private let pipeline = ImagePipeline.shared
  private let prefetcher = ImagePrefetcher()

  fileprivate init() {}

  func prefetch(_ urls: [URL]) async {
    log.debug("prefetching: \(urls)")

    prefetcher.startPrefetching(with: urls)
  }

  func fetch(_ url: URL) async throws -> UIImage {
    try await pipeline.image(for: url)
  }
}
