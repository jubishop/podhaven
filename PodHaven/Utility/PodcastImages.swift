// Copyright Justin Bishop, 2024 

import Foundation
import Nuke

struct PodcastImages: Sendable {
  static let shared: PodcastImages = {
    PodcastImages()
  }()

  private let prefetcher = ImagePrefetcher()

  func prefetch(_ urls: [URL]) {
    print("Now prefetching: \(urls)")
    prefetcher.startPrefetching(with: urls)
  }
}

