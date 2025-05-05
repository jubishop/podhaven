// Copyright Justin Bishop, 2025

import Foundation

enum PermissionError: KittedError {
  case denied(String)
  case caught(Error)

  var userFriendlyMessage: String {
    switch self {
    case .denied(let permission):
      return "Denied permission: \(permission)"
    case .caught(let error):
      return nestedUserFriendlyCaughtMessage(error)
    }
  }
}
