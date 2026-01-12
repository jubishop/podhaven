// Copyright Justin Bishop, 2025

import Foundation
import ReadableErrorMacro

@ReadableError
enum ShareError: ReadableError, CatchingError {
  case extractionFailure(URL)
  case noFeedURLFound
  case noIdentifierFound(URL)
  case noEpisodeFound
  case unsupportedURL(URL)
  case caught(any Error)

  var message: String {
    switch self {
    case .extractionFailure(let url):
      return "Failed to extract share url from: \(url)"
    case .noFeedURLFound:
      return "Could not find a valid RSS feed for this podcast"
    case .noIdentifierFound(let url):
      return "Could not extract podcast information from URL: \(url)"
    case .noEpisodeFound:
      return "Could not find episode information"
    case .unsupportedURL(let url):
      return "The URL: \(url) is not supported for importing podcasts"
    case .caught: return ""
    }
  }
}
