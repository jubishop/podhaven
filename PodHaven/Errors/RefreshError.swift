// Copyright Justin Bishop, 2025

import ErrorKit
import Foundation

enum RefreshError: KittedError {
  case parseFailure(podcastSeries: PodcastSeries, caught: Error)
  case caught(Error)

  var userFriendlyMessage: String {
    switch self {
    case .parseFailure(let podcastSeries, let error):
      return
        """
        Failed to refresh podcast series
          PodcastSeries: \(podcastSeries.toString)
          FeedURL: \(podcastSeries.podcast.feedURL)
        \(Self.nestedUserFriendlyCaughtMessage(for: error))
        """
    case .caught(let error):
      return nestedUserFriendlyCaughtMessage(error)
    }
  }
}
