// Copyright Justin Bishop, 2025 

import Foundation

struct SearchedPodcast: Sendable, Hashable {
  let unsavedPodcast: UnsavedPodcast
  let searchText: String
}
