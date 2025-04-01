// Copyright Justin Bishop, 2025

import Foundation

struct SearchedPodcastByTerm: SearchedPodcast, Sendable, Hashable {
  let searchedText: String
  let unsavedPodcast: UnsavedPodcast
}
