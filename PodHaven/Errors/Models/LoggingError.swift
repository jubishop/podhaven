// Copyright Justin Bishop, 2025

import Foundation
import ReadableErrorMacro

@ReadableError
enum LoggingError: ReadableError {
  case dataEncodingFailure(String)
  case truncationNegativeBytes(Int)
  case truncationNoNewlineFound(Int)

  var message: String {
    switch self {
    case .dataEncodingFailure(let string):
      return "Failed to encode string to UTF-8 data: \(string)"
    case .truncationNegativeBytes(let bytesToRemove):
      return "Truncation resulted in negative bytes to remove: \(bytesToRemove)"
    case .truncationNoNewlineFound(let byteOffset):
      return "Could not find newline after byte \(byteOffset) for truncation"
    }
  }
}
