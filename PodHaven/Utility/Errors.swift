// Copyright Justin Bishop, 2024

import Foundation

enum PlaybackError: Error, LocalizedError, Sendable {
  case notPlayable(URL)
  case noURL(Episode)

  var errorDescription: String {
    switch self {
    case .notPlayable(let url):
      return "The asset at \(url) cannot be played."
    case .noURL(let episode):
      return "The episode: \(episode.toString) has no URL."
    }
  }
}

enum DownloadError: Error, LocalizedError, Sendable {
  case invalidResponse
  case invalidStatusCode(Int)
  case networkError(String)
  case cancelled

  var errorDescription: String {
    switch self {
    case .invalidResponse:
      return "Received an invalid response from the server."
    case .invalidStatusCode(let statusCode):
      return "Received HTTP status code \(statusCode)."
    case .networkError(let message):
      return "A network error occurred: \"\(message)\""
    case .cancelled:
      return "The download was cancelled."
    }
  }
}

enum FeedError: Error, LocalizedError, Sendable {
  case failedLoad(URL)
  case failedParse(String)
  case noRSS

  var errorDescription: String {
    switch self {
    case .failedLoad(let url):
      return "Failed to load URL: \(url)"
    case .failedParse(let message):
      return "Failed to parse RSS feed: \"\(message)\""
    case .noRSS:
      return "No RSS feed found."
    }
  }
}
