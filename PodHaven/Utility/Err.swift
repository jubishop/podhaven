// Copyright Justin Bishop, 2025

import Foundation

enum Err: Error, LocalizedError, Sendable {
  case msg(String)
  case cancelled

  var errorDescription: String {
    switch self {
      case .msg(let msg): return msg
      case .cancelled: return "Cancelled"
    }
  }
}
