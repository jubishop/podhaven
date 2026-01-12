// Copyright Justin Bishop, 2025

import Foundation
import ReadableErrorMacro

@ReadableError
enum FeedError: ReadableError, CatchingError {
  case parseFailure(url: FeedURL, caught: any Error)
  case caught(any Error)

  var message: String {
    switch self {
    case .parseFailure(let url, _):
      return "Failed to parse feed at \(url)"
    case .caught: return ""
    }
  }
}
