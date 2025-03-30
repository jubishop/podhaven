// Copyright Justin Bishop, 2025 

import Foundation

struct SearchedPodcastByTitle: PodcastSearchContext, Sendable, Hashable {
  var contextLabel: String { searchText }
  let searchText: String
  let unsavedPodcast: UnsavedPodcast
}
