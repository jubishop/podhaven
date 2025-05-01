// Copyright Justin Bishop, 2025

import ErrorKit
import Foundation

enum FeedError: KittedError {
  case caught(Error)

  var userFriendlyMessage: String {
    switch self {
    case .caught(let error):
      return ErrorKit.userFriendlyMessage(for: error)
    }
  }
}
