// Copyright Justin Bishop, 2025

import Foundation

struct SearchedEpisodeByPerson: Sendable, Hashable {
  let searchedText: String
  let unsavedPodcastEpisode: UnsavedPodcastEpisode
}
