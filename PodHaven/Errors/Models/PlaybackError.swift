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
          MediaGUID: \(podcastEpisode.episode.unsaved.id)
        """
    case .mediaNotPlayable(let podcastEpisode):
      return
        """
        MediaGUID Not Playable
          PodcastEpisode: \(podcastEpisode.toString)
          MediaGUID: \(podcastEpisode.episode.unsaved.id)
        """
    case .settingCurrentTimeOnNil(let cmTime):
      return "Setting current time on nil player item with CMTime: \(cmTime)"
    case .caught: return ""
    }
  }
}
