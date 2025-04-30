// Copyright Justin Bishop, 2025

import ErrorKit
import Foundation

enum PlaybackError: Throwable, Catching {
  case mediaNotPlayable(PodcastEpisode)
  case caught(Error)

  var userFriendlyMessage: String {
    switch self {
    case .mediaNotPlayable(let podcastEpisode):
      return
        """
        MediaURL Not Playable.
          PodcastEpisode: \(podcastEpisode.toString)
          MediaURL: \(podcastEpisode.episode.media)
        """
    case .caught(let error):
      return ErrorKit.userFriendlyMessage(for: error)
    }
  }
}
