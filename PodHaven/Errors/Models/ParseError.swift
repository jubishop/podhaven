// Copyright Justin Bishop, 2025

import Foundation
import ReadableErrorMacro

@ReadableError
enum ParseError: ReadableError, CatchingError {
  case exportFailure(_ error: any Error)
  case invalidData(data: Data, caught: any Error)
  case invalidMediaURL(MediaURL)
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
    case .missingImage(let title):
      return "Missing required image attribute for \(title)"
    case .missingMediaURL(let title):
      return "Missing required enclosure media url for \(title)"
    case .caught: return ""
    }
  }
}
