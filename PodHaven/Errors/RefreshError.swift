// Copyright Justin Bishop, 2025

import Foundation
import ReadableErrorMacro

@ReadableError
enum RefreshError: ReadableError, CatchingError {
  case parseFailure(podcastSeries: PodcastSeries, caught: Error)
  case caught(Error)

  var message: String {
    switch self {
    case .parseFailure(let podcastSeries, _):
      return
        """
        Failed to refresh podcast series
          PodcastSeries: \(podcastSeries.toString)
          FeedURL: \(podcastSeries.podcast.feedURL)
        """
    default: return ""
    }
  }
}
