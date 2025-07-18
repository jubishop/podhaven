// Copyright Justin Bishop, 2025

import Foundation
import ReadableErrorMacro

@ReadableError
enum ShareError: ReadableError, CatchingError {
  case extractionFailure(URL)
  case fetchFailure(request: URLRequest, caught: Error)
  case invalidURL(URL)
  case noFeedURLFound(String)
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
    case .invalidURL:
      return "This URL is invalid"
    case .noFeedURLFound:
      return "Could not find a valid RSS feed for this podcast"
    case .noIdentifierFound:
      return "Could not extract podcast information from this URL"
    case .parseFailure:
      return "Failed to parse response"
    case .unsupportedURL:
      return "This URL is not supported for importing podcasts"
    case .caught: return ""
    }
  }
}
