// Copyright Justin Bishop, 2025

import Foundation
import ReadableErrorMacro

@ReadableError
enum DownloadError: ReadableError, CatchingError {
  case cancelled(URL)
  case invalidRequest(URLRequest)
  case loadFailure(URL)
  case notOKResponseCode(code: Int, url: URL)
  case caught(any Error)

  var message: String {
    switch self {
    case .cancelled(let url):
      return "Cancelled load of \(url)"
    case .invalidRequest(let request):
      return "Invalid URLRequest: \(request)"
    case .loadFailure(let url):
      return "Failed to load \(url)"
    case .notOKResponseCode(let code, let url):
      return "Received HTTP response code: \(code), for: \(url)"
    case .caught: return ""
    }
  }
}
