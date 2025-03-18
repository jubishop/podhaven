// Copyright Justin Bishop, 2025 

import Foundation

struct SearchedPodcastByTitle: Sendable, Hashable {
  let unsavedPodcast: UnsavedPodcast
  let searchText: String
}
