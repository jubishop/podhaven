// Copyright Justin Bishop, 2025

import Foundation
import ReadableErrorMacro

@ReadableError
enum RefreshError: ReadableError, CatchingError {
  case parseFailure(podcastSeries: PodcastSeries, caught: any Error)
  case caught(any Error)

  var message: String {
    switch self {
    case .parseFailure(let podcastSeries, _):
      return
        """
        Failed to refresh podcast series
          PodcastSeries: \(podcastSeries.toString)
          FeedURL: \(podcastSeries.podcast.feedURL)
        """
    case .caught: return ""
    }
  }
}
