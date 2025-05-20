// Copyright Justin Bishop, 2025

import Foundation
import ReadableErrorMacro

@ReadableError
enum DownloadError: ReadableError, CatchingError {
  case cancelled(URL)
  case loadFailure(URL)
  case notHTTPURLResponse(URL)
  case notOKResponseCode(code: Int, url: URL)
  case caught(Error)

  var message: String {
    switch self {
    case .cancelled(let url):
      return "Cancelled load of \(url)"
    case .loadFailure(let url):
      return "Failed to load \(url)"
    case .notHTTPURLResponse(let url):
      return "Received non-HTTP URL response for: \(url)"
    case .notOKResponseCode(let code, let url):
      return "Received HTTP response code: \(code), for: \(url)"
    default: return ""
    }
  }
}
