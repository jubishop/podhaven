// Copyright Justin Bishop, 2025

import Foundation
import ReadableErrorMacro

@ReadableError
enum ParseError: ReadableError {
  case invalidData(data: Data, caught: Error)
  case mergingDifferentFeedURLs(parsing: FeedURL, merging: FeedURL?)
  case mergingDifferentMediaURLs(parsing: MediaURL, merging: MediaURL?)
  case missingImageField

  var message: String {
    switch self {
    case .invalidData(let data, _):
      return
        """
        Invalid data
          Data size: \(data.count)
        """
    case .mergingDifferentFeedURLs(let parsing, let merging):
      return
        """
        Merging divergent FeedURLs:
          Parsing: \(parsing)
          Merging: \(String(describing: merging))
        """
    case .mergingDifferentMediaURLs(let parsing, let merging):
      return
        """
        Merging divergent MediaURLs:
          Parsing: \(parsing)
          Merging: \(String(describing: merging))
        """
    case .missingImageField:
      return "Missing required image field"
    }
  }
}
