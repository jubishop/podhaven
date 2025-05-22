// Copyright Justin Bishop, 2025

import Foundation
import ReadableErrorMacro

@ReadableError
enum FeedError: ReadableError, CatchingError {
  case parseFailure(url: FeedURL, caught: Error)
  case caught(Error)

  var message: String {
    switch self {
    case .parseFailure(let url, _):
      return "Failed to parse feed at \(url)"
    case .caught: return ""
    }
  }
}
