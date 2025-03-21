// Copyright Justin Bishop, 2025 

import Foundation

struct SearchedPodcastByTerm: Sendable, Hashable {
  let unsavedPodcast: UnsavedPodcast
  let searchText: String
}
