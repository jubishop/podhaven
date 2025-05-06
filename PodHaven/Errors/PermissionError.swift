// Copyright Justin Bishop, 2025

import Foundation

enum PermissionError: ReadableError {
  case denied(String)

  var message: String {
    switch self {
    case .denied(let permission):
      return "Denied permission: \(permission)"
    }
  }
}
