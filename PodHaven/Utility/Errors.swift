// Copyright Justin Bishop, 2024

import Foundation

enum DownloadError: Error, LocalizedError, Sendable {
  case invalidResponse
  case invalidStatusCode(Int)
  case networkError(Error)
  case cancelled

  var errorDescription: String {
    switch self {
    case .invalidResponse:
      return "Received an invalid response from the server."
    case .invalidStatusCode(let statusCode):
      return "Received HTTP status code \(statusCode)."
    case .networkError(let error):
      return "A network error occurred: \(error.localizedDescription)"
    case .cancelled:
      return "The download was cancelled."
    }
  }
}

enum FeedError: Error, LocalizedError, Sendable {
  case failedLoad(URL)
  case failedParse(Error)
  case noRSS

  var errorDescription: String {
    switch self {
    case .failedLoad(let url):
      return "Failed to load URL: \(url)"
    case .failedParse(let error):
      return "Failed to parse RSS feed: \"\(error)\""
    case .noRSS:
      return "No RSS feed found."
    }
  }
}
