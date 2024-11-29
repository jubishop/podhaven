// Copyright Justin Bishop, 2024

import Foundation

enum DBError: Error, LocalizedError, Sendable, Equatable {
  case validationError(String)
  case updateError(String)

  var errorDescription: String? {
    switch self {
    case .validationError(let errorMessage), .updateError(let errorMessage):
      return errorMessage
    }
  }
}
