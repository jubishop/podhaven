// Copyright Justin Bishop, 2025

import Foundation
import ReadableErrorMacro

@ReadableError
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
