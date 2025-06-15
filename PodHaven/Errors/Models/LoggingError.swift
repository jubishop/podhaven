// Copyright Justin Bishop, 2025

import Foundation
import ReadableErrorMacro

@ReadableError
enum LoggingError: ReadableError {
  case jsonStringCreationFailure(FileLogEntry)

  var message: String {
    switch self {
    case .jsonStringCreationFailure(let fileLogEntry):
      return "Failed to make JSON string from log entry: \(fileLogEntry)"
    }
  }
}
