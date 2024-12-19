// Copyright Justin Bishop, 2024

import Foundation
import Nuke
import SwiftUI

struct Images: Sendable {
  static let shared = Images()

  private let pipeline = ImagePipeline.shared
  private let prefetcher = ImagePrefetcher()

  private init() {}

  func prefetch(_ urls: [URL]) {
    prefetcher.startPrefetching(with: urls)
  }

  func fetchImage(_ url: URL) async throws -> UIImage {
    try await pipeline.image(for: url)
  }
}
