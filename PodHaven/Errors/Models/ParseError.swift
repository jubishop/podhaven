// Copyright Justin Bishop, 2025

import Foundation
import ReadableErrorMacro

@ReadableError
enum ParseError: ReadableError, CatchingError {
  case exportFailure(_ error: any Error)
  case invalidData(data: Data, caught: Error)
  case invalidMediaURL(MediaURL)
  case mergingDifferentFeedURLs(parsing: FeedURL, merging: FeedURL?)
  case mergingDifferentMediaURLs(parsing: MediaURL, merging: MediaURL?)
  case missingImage(String)
  case missingMediaURL(String)
  case caught(_ error: any Error)

  var message: String {
    switch self {
    case .exportFailure(_):
      return "Export failed"
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
    case .caught: return ""
    }
  }
}
