// Copyright Justin Bishop, 2025

import Foundation
import ReadableErrorMacro

@ReadableError
enum LoggingError: ReadableError {
  case failedToMakeJSONString(FileLogEntry)

  var message: String {
    switch self {
    case .failedToMakeJSONString(let fileLogEntry):
      return "Failed to make JSON string from log entry: \(fileLogEntry)"
    }
  }
}
