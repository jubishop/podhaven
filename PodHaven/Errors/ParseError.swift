// Copyright Justin Bishop, 2025

import Foundation

enum ParseError: KittedError {
  case invalidData(data: Data, caught: Error)
  case mergePreconditionFailed(String)
  case missingField(String)
  case caught(Error)

  var userFriendlyMessage: String {
    switch self {
    case .invalidData(let data, let error):
      return
        """
        Invalid data
          Data: \(String(decoding: data, as: UTF8.self))
        \(Self.nestedUserFriendlyCaughtMessage(for: error))
        """
    case .mergePreconditionFailed(let message):
      return "Parsed item merge precondition failed: \(message)"
    case .missingField(let field):
      return "Missing required field: \(field)"
    case .caught(let error):
      return nestedUserFriendlyCaughtMessage(error)
    }
  }
}
