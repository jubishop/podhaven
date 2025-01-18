// Copyright Justin Bishop, 2025

import Foundation

enum Err: Error, LocalizedError, Sendable {
  case msg(String)
  case cancelled

  var errorDescription: String {
    switch self {
    case .msg(let message): return message
    case .cancelled: return "Cancelled"
    }
  }

  var localizedDescription: String { errorDescription }
}
