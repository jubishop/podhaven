// Copyright Justin Bishop, 2025

import Foundation
import ReadableErrorMacro

@ReadableError
enum CacheError: ReadableError, CatchingError {
  case applicationSupportDirectoryNotFound
  case episodeNotFound(Episode.ID)
  case failedToDownload(podcastEpisode: PodcastEpisode, caught: Error)
  case mediaNotPlayable(Episode)
  case caught(Error)

  var message: String {
    switch self {
    case .applicationSupportDirectoryNotFound:
      return "Caches directory not found for cache storage"
    case .episodeNotFound(let episodeID):
      return "Episode \(episodeID) not found for cache operation"
    case .failedToDownload(let podcastEpisode, _):
      return "Failed to download episode: \(podcastEpisode.toString)"
    case .mediaNotPlayable(let episode):
      return
        """
        MediaGUID Not Playable
          Episode: \(episode.toString)
          MediaGUID: \(episode.unsaved.id)
        """
    case .caught: return ""
    }
  }
}
