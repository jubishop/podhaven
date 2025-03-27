// Copyright Justin Bishop, 2025

import Foundation

struct SearchedEpisodeByPerson: Sendable, Hashable {
  let unsavedPodcastEpisode: UnsavedPodcastEpisode
  let searchText: String
}
