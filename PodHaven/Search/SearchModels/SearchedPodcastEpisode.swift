// Copyright Justin Bishop, 2025

import Foundation

struct SearchedPodcastEpisode: Hashable {
  let searchedText: String
  let episode: any EpisodeDisplayable

  func hash(into hasher: inout Hasher) {
    hasher.combine(searchedText)
    hasher.combine(episode.mediaURL)
  }

  static func == (lhs: SearchedPodcastEpisode, rhs: SearchedPodcastEpisode) -> Bool {
    lhs.searchedText == rhs.searchedText && lhs.episode.mediaURL == rhs.episode.mediaURL
  }
}
