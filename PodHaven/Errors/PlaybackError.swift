// Copyright Justin Bishop, 2025

import ErrorKit
import Foundation

enum PlaybackError: KittedError {
  case mediaNotPlayable(PodcastEpisode)
  case caught(Error)

  var nestableUserFriendlyMessage: String {
    switch self {
    case .mediaNotPlayable(let podcastEpisode):
      return
        """
        MediaURL Not Playable
          PodcastEpisode: \(podcastEpisode.toString)
          MediaURL: \(podcastEpisode.episode.media)
        """
    case .caught(let error):
      return userFriendlyCaughtMessage(caught: error)
    }
  }
}
