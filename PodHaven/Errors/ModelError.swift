// Copyright Justin Bishop, 2025

import ErrorKit
import Foundation

enum ModelError: KittedError {
  case podcastInitializationFailure(feedURL: FeedURL, title: String, caught: Error)
  case caught(Error)

  var userFriendlyMessage: String {
    switch self {
    case .podcastInitializationFailure(let feedURL, let title, let error):
      return
        """
        Failed to create podcast
          FeedURL: \(feedURL)
          Title: \(title)
          Caught: \(Self.nestedUserFriendlyMessage(for: error))
        """
    case .caught(let error):
      return nestedUserFriendlyCaughtMessage(error)
    }
  }
}
