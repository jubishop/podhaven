// Copyright Justin Bishop, 2025

import ErrorKit
import Foundation

enum DownloadError: KittedError {
  case cancelled(URL)
  case loadFailure(URL)
  case caught(Error)

  var nestableUserFriendlyMessage: String {
    switch self {
    case .cancelled(let url):
      return "Cancelled load of \(url)"
    case .loadFailure(let url):
      return "Failed to load \(url)"
    case .caught(let error):
      return userFriendlyCaughtMessage(caught: error)
    }
  }
}
