// Copyright Justin Bishop, 2025

import AVFoundation
import Foundation
import ReadableErrorMacro

@ReadableError
enum PlaybackError: ReadableError, CatchingError {
  case currentItemChangedWhenPaused(MediaURL?)
  case endedEpisodeDoesNotMatch(podcastEpisode: PodcastEpisode?, mediaURL: MediaURL)
  case endedEpisodeNotFound(MediaURL)
  case loadFailure(podcastEpisode: PodcastEpisode, caught: Error)
  case mediaNotPlayable(PodcastEpisode)
  case settingCurrentTimeOnNil(CMTime)
  case caught(Error)

  var message: String {
    switch self {
    case .currentItemChangedWhenPaused(let mediaURL):
      return "Current item changed when paused with MediaURL: \(String(describing: mediaURL))"
    case .endedEpisodeDoesNotMatch(let podcastEpisode, let mediaURL):
      return
        """
        Ended episode that doesn't match cached current episode
          PodcastEpisode: \(String(describing: podcastEpisode?.toString))
          MediaURL: \(mediaURL)
        """
    case .endedEpisodeNotFound(let mediaURL):
      return "Ended episode not found with MediaURL: \(mediaURL)"
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
    case .caught(_): return ""
    }
  }
}
