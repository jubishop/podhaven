// Copyright Justin Bishop, 2025

import ErrorKit
import Foundation

enum FeedError: KittedError {
  case caught(Error)

  var nestableUserFriendlyMessage: String {
    switch self {
    case .caught(let error):
      return userFriendlyCaughtMessage(error)
    }
  }
}
