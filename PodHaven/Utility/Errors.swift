// Copyright Justin Bishop, 2024

import Foundation

enum DBError: Error, LocalizedError, Sendable, Equatable {
  case validationError(String)

  var errorDescription: String? {
    switch self {
    case .validationError(let errorMessage):
      return errorMessage
    }
  }
}
