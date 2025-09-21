// Copyright Justin Bishop, 2025

import ReadableErrorMacro

@ReadableError
enum AppInfoError: ReadableError {
  case unverifiedAppTransaction
  case unknownAppTransactionEnvironment(environment: String)

  var message: String {
    switch self {
    case .unverifiedAppTransaction:
      return "Unable to verify App Store transaction for environment detection"
    case .unknownAppTransactionEnvironment(let environment):
      return "Received unknown App Store transaction environment: \(environment)"
    }
  }
}
