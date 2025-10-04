// Copyright Justin Bishop, 2025

import Foundation
import ReadableErrorMacro

@ReadableError
enum ShareError: ReadableError, CatchingError {
  case extractionFailure(URL)
  case fetchFailure(request: URLRequest, caught: Error)
  case noFeedURLFound
  case noIdentifierFound(URL)
  case noEpisodeFound
  case parseFailure(data: Data, caught: Error)
  case unsupportedURL(URL)
  case caught(Error)

  var message: String {
    switch self {
    case .extractionFailure(let url):
      return "Failed to extract share url from: \(url)"
    case .fetchFailure(let request, _):
      return "Failed to fetch url: \(request)"
    case .noFeedURLFound:
      return "Could not find a valid RSS feed for this podcast"
    case .noIdentifierFound(let url):
      return "Could not extract podcast information from URL: \(url)"
    case .noEpisodeFound:
      return "Could not find episode information"
    case .parseFailure(let data, _):
      return "Failed to parse data: \(String(decoding: data, as: UTF8.self))"
    case .unsupportedURL(let url):
      return "The URL: \(url) is not supported for importing podcasts"
    case .caught: return ""
    }
  }
}
