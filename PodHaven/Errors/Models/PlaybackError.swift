// Copyright Justin Bishop, 2025

import Foundation
import ReadableErrorMacro

@ReadableError
enum PlaybackError: ReadableError, CatchingError {
  case finishedEpisodeIsNil
  case loadingPodcastAlreadyPlaying(PodcastEpisode)
  case loadFailure(podcastEpisode: PodcastEpisode, caught: Error)
  case mediaNotPlayable(PodcastEpisode)
  case caught(Error)

  var message: String {
    switch self {
    case .finishedEpisodeIsNil:
      return "Finished episode but current episode is nil?"
    case .loadingPodcastAlreadyPlaying(let podcastEpisode):
      return "Loading podcast \(podcastEpisode.toString) that's already loaded"
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
