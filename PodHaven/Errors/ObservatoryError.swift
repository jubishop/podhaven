// Copyright Justin Bishop, 2025

import Foundation

enum ObservatoryError: ReadableError {
  case recordNotFound(type: Any.Type, id: Int64)

  var message: String {
    switch self {
    case .recordNotFound(let type, let id):
      return "Expected record of type \(String(describing: type)) with ID \(id) not found"
    }
  }
}
