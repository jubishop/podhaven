// Copyright Justin Bishop, 2025

import Foundation
import ReadableErrorMacro

@ReadableError
enum ShareError: ReadableError, CatchingError {
  case extractionFailure(URL)
  case fetchFailure(request: URLRequest, caught: Error)
  case invalidURL(URL)
  case noFeedURLFound
  case noIdentifierFound(URL)
  case parseFailure(Data)
  case unsupportedURL(URL)
  case caught(Error)

  var message: String {
    switch self {
    case .extractionFailure(let url):
      return "Failed to extract podcast information from url: \(url)"
    case .fetchFailure(let request, _):
      return "Failed to fetch url: \(request)"
    case .invalidURL(let url):
      return "This URL: \(url) is invalid"
    case .noFeedURLFound:
      return "Could not find a valid RSS feed for this podcast"
    case .noIdentifierFound(let url):
      return "Could not extract podcast information from URL: \(url)"
    case .parseFailure:
      return "Failed to parse response"
    case .unsupportedURL(let url):
      return "The URL: \(url) is not supported for importing podcasts"
    case .caught: return ""
    }
  }
}
