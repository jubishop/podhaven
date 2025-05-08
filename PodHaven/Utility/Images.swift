// Copyright Justin Bishop, 2025

import Factory
import Foundation
import Nuke
import SwiftUI

extension Container {
  var images: Factory<Images> {
    Factory(self) { Images() }.scope(.cached)
  }
}

struct Images: Sendable {
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
