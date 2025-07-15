// Copyright Justin Bishop, 2025

import Foundation
import ReadableErrorMacro

@ReadableError
enum ShareError: ReadableError {
  case addPodcastSuccess(String)
  case alreadySubscribed(String)
  case fetchFailure(request: URLRequest, caught: Error)
  case invalidURL(URL)
  case noFeedURLFound(String)
  case noIdentifierFound(URL)
  case parseFailure(Data)
  case subscriptionSuccess(String)
  case unsupportedURL(URL)

  var message: String {
    switch self {
    case .addPodcastSuccess(let title):
      return "Successfully added and subscribed to \(title)"
    case .alreadySubscribed(let title):
      return "You're already subscribed to \(title)"
    case .fetchFailure(let request, _):
      return "Failed to fetch url: \(request)"
    case .invalidURL:
      return "This URL is invalid"
    case .noFeedURLFound:
      return "Could not find a valid RSS feed for this podcast"
    case .noIdentifierFound:
      return "Could not extract podcast information from this URL"
    case .parseFailure:
      return "Failed to parse response"
    case .subscriptionSuccess(let title):
      return "Successfully subscribed to \(title)"
    case .unsupportedURL:
      return "This URL is not supported for importing podcasts"
    }
  }
}
