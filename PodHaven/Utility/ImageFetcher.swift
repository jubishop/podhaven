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
  private let pipeline = ImagePipeline.shared
  private let prefetcher = ImagePrefetcher()

  fileprivate init() {}

  func prefetch(_ urls: [URL]) {
    prefetcher.startPrefetching(with: urls)
  }

  func fetchImage(_ url: URL) async throws -> UIImage {
    try await pipeline.image(for: url)
  }
}
