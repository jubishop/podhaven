// Copyright Justin Bishop, 2024

import Foundation
import Nuke

struct PodcastImages: Sendable {
  static let shared = { PodcastImages() }()

  private let prefetcher = ImagePrefetcher()

  private init() {}

  func prefetch(_ urls: [URL]) {
    prefetcher.startPrefetching(with: urls)
  }
}
