// Copyright Justin Bishop, 2025

import Foundation
import ReadableErrorMacro

@ReadableError
enum PlaybackError: ReadableError, CatchingError {
  case loadFailure(podcastEpisode: PodcastEpisode, caught: Error)
  case mediaNotPlayable(PodcastEpisode)
  case caught(Error)

  var message: String {
    switch self {
    case .loadFailure(let podcastEpisode, _):
      return
        """
        Failed to load avAsset
          PodcastEpisode: \(podcastEpisode.toString)
          MediaURL: \(podcastEpisode.episode.media)
        """
    case .mediaNotPlayable(let podcastEpisode):
      return
        """
        MediaURL Not Playable
          PodcastEpisode: \(podcastEpisode.toString)
          MediaURL: \(podcastEpisode.episode.media)
        """
    case .caught(_): return ""
    }
  }
}
