// Copyright Justin Bishop, 2025

import Foundation
import ReadableErrorMacro

@ReadableError
enum PlaybackError: ReadableError {
  case finishedEpisodeIsNil
  case loadingPodcastAlreadyPlaying(PodcastEpisode)
  case loadingPodcastWhenAlreadyLoading(
    currentPodcastEpisode: PodcastEpisode?,
    loadingPodcastEpisode: PodcastEpisode
  )
  case loadFailure(podcastEpisode: PodcastEpisode, caught: Error)
  case mediaNotPlayable(PodcastEpisode)

  var message: String {
    switch self {
    case .finishedEpisodeIsNil:
      return "Finished episode but current episode is nil?"
    case .loadingPodcastAlreadyPlaying(let podcastEpisode):
      return "Loading podcast \(podcastEpisode.toString) that's already loaded"
    case .loadingPodcastWhenAlreadyLoading(let currentPodcastEpisode, let loadingPodcastEpisode):
      return
        """
        Loading podcast when loading state is already .loaded
          Current Podcast Episode: \(String(describing: currentPodcastEpisode?.toString))
          Loading Podcast Episode: \(loadingPodcastEpisode.toString)
        """
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
    }
  }
}
