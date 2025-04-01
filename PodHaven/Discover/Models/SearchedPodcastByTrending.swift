// Copyright Justin Bishop, 2025

import Foundation

struct SearchedPodcastByTrending: SearchedPodcast, Sendable, Hashable {
  let category: String
  let unsavedPodcast: UnsavedPodcast

  var searchedText: String { category }
}
