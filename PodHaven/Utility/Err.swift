// Copyright Justin Bishop, 2025

import Foundation

enum Err: Error, LocalizedError, Sendable {
  case msg(String)
  case cancelled(String? = nil)

  static func andPrint(_ error: Err) -> Self {
    print(error.errorDescription)
    return error
  }

  var errorDescription: String {
    switch self {
    case .msg(let message): return message
    case .cancelled(let message):
      guard let message = message
      else { return "Cancelled" }

      return "Cancelled: \(message)"
    }
  }

  var localizedDescription: String { errorDescription }
}
