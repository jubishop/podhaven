// Copyright Justin Bishop, 2025

import AVFoundation
import Foundation
import ReadableErrorMacro

@ReadableError
enum PlaybackError: ReadableError, CatchingError {
  case endedEpisodeNotFound(Episode.ID?)
  case loadFailure(podcastEpisode: PodcastEpisode, caught: Error)
  case mediaNotPlayable(PodcastEpisode)
  case settingCurrentTimeOnNil(CMTime)
  case caught(Error)

  var message: String {
    switch self {
    case .endedEpisodeNotFound(let episodeID):
      return "Ended episode not found with Episode ID: \(String(describing: episodeID))"
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
    case .settingCurrentTimeOnNil(let cmTime):
      return "Setting current time on nil player item with CMTime: \(cmTime)"
    case .caught: return ""
    }
  }
}
