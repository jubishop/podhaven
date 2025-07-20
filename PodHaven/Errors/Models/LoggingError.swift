// Copyright Justin Bishop, 2025

import Foundation
import ReadableErrorMacro

@ReadableError
enum LoggingError: ReadableError {
  case backgroundTaskInvalid
  case jsonStringCreationFailure(FileLogEntry)
  case logFileDoesNotExist
  case logFileHasNotGrown

  var message: String {
    switch self {
    case .backgroundTaskInvalid:
      return "Background task was invalid?"
    case .jsonStringCreationFailure(let fileLogEntry):
      return "Failed to make JSON string from log entry: \(fileLogEntry)"
    case .logFileDoesNotExist:
      return "Log file does not exist?"
    case .logFileHasNotGrown:
      return "Log file has not grown since last truncation?"
    }
  }
}
