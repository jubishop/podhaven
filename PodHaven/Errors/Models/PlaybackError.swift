// Copyright Justin Bishop, 2025

import AVFoundation
import Foundation
import ReadableErrorMacro

@ReadableError
enum PlaybackError: ReadableError, CatchingError {
  case loadFailure(podcastEpisode: PodcastEpisode, caught: Error)
  case mediaNotPlayable(PodcastEpisode)
  case settingCurrentTimeOnNil(CMTime)
  case caught(Error)

  var message: String {
    switch self {
    case .loadFailure(let podcastEpisode, _):
      return
        """
        Failed to load avAsset
          PodcastEpisode: \(podcastEpisode.toString)
          MediaURL: \(podcastEpisode.episode.mediaURL)
        """
    case .mediaNotPlayable(let podcastEpisode):
      return
        """
        MediaURL Not Playable
          PodcastEpisode: \(podcastEpisode.toString)
          MediaURL: \(podcastEpisode.episode.mediaURL)
        """
    case .settingCurrentTimeOnNil(let cmTime):
      return "Setting current time on nil player item with CMTime: \(cmTime)"
    case .caught: return ""
    }
  }
}
