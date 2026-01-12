// Copyright Justin Bishop, 2025

import Foundation
import ReadableErrorMacro

@ReadableError
enum ModelError: ReadableError {
  case podcastInitializationFailure(feedURL: FeedURL, title: String, caught: any Error)

  var message: String {
    switch self {
    case .podcastInitializationFailure(let feedURL, let title, _):
      return
        """
        Failed to create podcast
          FeedURL: \(feedURL)
          Title: \(title)
        """
    }
  }
}
