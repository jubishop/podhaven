// Copyright Justin Bishop, 2025

import ErrorKit
import Foundation

enum FeedError: KittedError {
  case parseFailure(url: FeedURL, caught: Error)
  case caught(Error)

  var userFriendlyMessage: String {
    switch self {
    case .parseFailure(let url, let error):
      return
        """
        Failed to parse feed at \(url)
          Caught: \(Self.nestedUserFriendlyMessage(for: error))
        """
    case .caught(let error):
      return nestedUserFriendlyCaughtMessage(error)
    }
  }
}
