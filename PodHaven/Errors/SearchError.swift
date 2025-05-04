// Copyright Justin Bishop, 2025

import ErrorKit
import Foundation

enum SearchError: KittedError {
  case fetchFailure(request: URLRequest, networkError: NetworkError)
  case parseFailure(Data)
  case caught(Error)

  var userFriendlyMessage: String {
    switch self {
    case .fetchFailure(let request, let networkError):
      return
        """
        Failed to fetch url: \(request)
          \(ErrorKit.errorChainDescription(for: networkError, indent: "  "))
        """
    case .parseFailure:
      return "Failed to parse search response"
    case .caught(let error):
      return ErrorKit.userFriendlyMessage(for: error)
    }
  }
}
