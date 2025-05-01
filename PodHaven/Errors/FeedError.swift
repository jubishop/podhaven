// Copyright Justin Bishop, 2025

import ErrorKit
import Foundation

enum FeedError: KittedError {
  case downloadFailure(DownloadError)
  case caught(Error)

  var userFriendlyMessage: String {
    switch self {
    case .downloadFailure(let downloadError):
      return "Download task failed: \(downloadError)"
    case .caught(let error):
      return ErrorKit.userFriendlyMessage(for: error)
    }
  }
}
