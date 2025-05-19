// Copyright Justin Bishop, 2025

import Foundation
import ReadableErrorMacro

@ReadableError
enum RefreshError: ReadableError, CatchingError {
  case parseFailure(podcastSeries: PodcastSeries, caught: Error)
  case caught(Error)

  var message: String {
    switch self {
    case .parseFailure(let podcastSeries, let error):
      return
        """
        Failed to refresh podcast series
          PodcastSeries: \(podcastSeries.toString)
          FeedURL: \(podcastSeries.podcast.feedURL)
        \(ErrorKit.nestedCaughtMessage(for: error))
        """
    case .caught(let error):
      return ErrorKit.nestedCaughtMessage(for: error)
    }
  }
}
