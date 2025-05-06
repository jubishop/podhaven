// Copyright Justin Bishop, 2025

import Foundation

enum FeedError: ReadableError, CatchingError {
  case parseFailure(url: FeedURL, caught: Error)
  case caught(Error)

  var message: String {
    switch self {
    case .parseFailure(let url, let error):
      return
        """
        Failed to parse feed at \(url)
        \(ErrorKit.nestedCaughtMessage(for: error))
        """
    case .caught(let error):
      return ErrorKit.nestedCaughtMessage(for: error)
    }
  }
}
