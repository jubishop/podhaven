// Copyright Justin Bishop, 2025

import Foundation

enum PlaybackError: ReadableError {
  case mediaNotPlayable(PodcastEpisode)

  var message: String {
    switch self {
    case .mediaNotPlayable(let podcastEpisode):
      return
        """
        MediaURL Not Playable
          PodcastEpisode: \(podcastEpisode.toString)
          MediaURL: \(podcastEpisode.episode.media)
        """
    }
  }
}
