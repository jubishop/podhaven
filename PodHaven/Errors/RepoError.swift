// Copyright Justin Bishop, 2025

import ErrorKit
import Foundation

enum RepoError: KittedError {
  case readError(type: Any.Type, id: Int64)
  case caught(Error)

  var nestableUserFriendlyMessage: String {
    switch self {
    case .readError(let type, let id):
      return "Failed to read record of type \(String(describing: type)) with ID \(id)"
    case .caught(let error):
      return userFriendlyCaughtMessage(caught: error)
    }
  }
}
