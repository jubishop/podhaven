// Copyright Justin Bishop, 2025

import ErrorKit
import Foundation

enum DownloadError: KittedError {
  case cancelled(URL)
  case loadFailure(URL)
  case caught(Error)

  var userFriendlyMessage: String {
    switch self {
    case .cancelled(let url):
      return "Cancelled load of \(url)"
    case .loadFailure(let url):
      return "Failed to load \(url)"
    case .caught(let error):
      return ErrorKit.userFriendlyMessage(for: error)
    }
  }
}
