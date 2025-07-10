// Copyright Justin Bishop, 2025

import Foundation
import ReadableErrorMacro

@ReadableError
enum ParseError: ReadableError {
  case invalidData(data: Data, caught: Error)
  case invalidMediaURL(MediaURL)
  case mergingDifferentFeedURLs(parsing: FeedURL, merging: FeedURL?)
  case mergingDifferentMediaURLs(parsing: MediaURL, merging: MediaURL?)
  case missingImage(String)
  case missingMediaURL(String)

  var message: String {
    switch self {
    case .invalidData(let data, _):
      return
        """
        Invalid data
          Data size: \(data.count)
        """
    case .invalidMediaURL(let mediaURL):
      return "Invalid MediaURL: \(mediaURL)"
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
    case .missingImage(let title):
      return "Missing required image attribute for \(title)"
    case .missingMediaURL(let title):
      return "Missing required enclosure media url for \(title)"
    }
  }
}
