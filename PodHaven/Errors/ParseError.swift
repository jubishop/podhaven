// Copyright Justin Bishop, 2025

import Foundation
import ReadableErrorMacro

@ReadableError
enum ParseError: ReadableError {
  case invalidData(data: Data, caught: Error)
  case mergePreconditionFailed(String)
  case missingField(String)

  var message: String {
    switch self {
    case .invalidData(let data, let error):
      return
        """
        Invalid data
          Data: \(String(decoding: data, as: UTF8.self))
        \(ErrorKit.nestedCaughtMessage(for: error))
        """
    case .mergePreconditionFailed(let message):
      return "Parsed item merge precondition failed: \(message)"
    case .missingField(let field):
      return "Missing required field: \(field)"
    }
  }
}
