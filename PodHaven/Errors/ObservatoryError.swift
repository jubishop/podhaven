// Copyright Justin Bishop, 2025

import ErrorKit
import Foundation

enum ObservatoryError: KittedError {
  case recordNotFound(type: Any.Type, id: Int64)
  case caught(Error)

  var nestableUserFriendlyMessage: String {
    switch self {
    case .recordNotFound(let type, let id):
      return "Expected record of type \(String(describing: type)) with ID \(id) not found"
    case .caught(let error):
      return userFriendlyCaughtMessage(error)
    }
  }
}
