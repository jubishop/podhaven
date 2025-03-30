// Copyright Justin Bishop, 2025

import Foundation

struct TrendingPodcast: PodcastSearchContext, Sendable, Hashable {
  let category: String
  var contextLabel: String { category }
  let unsavedPodcast: UnsavedPodcast
}
