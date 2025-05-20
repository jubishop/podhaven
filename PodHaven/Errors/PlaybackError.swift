// Copyright Justin Bishop, 2025

import Foundation
import ReadableErrorMacro

@ReadableError
enum PlaybackError: ReadableError {
  case finisheEpisodeIsNil
  case mediaNotPlayable(PodcastEpisode)

  var message: String {
    switch self {
    case .finisheEpisodeIsNil:
      return "Finished episode but current episode is nil?"
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
