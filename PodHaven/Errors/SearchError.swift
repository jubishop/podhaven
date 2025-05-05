// Copyright Justin Bishop, 2025

import ErrorKit
import Foundation

enum SearchError: KittedError {
  case fetchFailure(request: URLRequest, caught: Error)
  case parseFailure(Data)
  case caught(Error)

  var userFriendlyMessage: String {
    switch self {
    case .fetchFailure(let request, let error):
      return
        """
        Failed to fetch url: \(request) ->
        Caught ->
          \(Self.nestedUserFriendlyMessage(for: error))
        """
    case .parseFailure:
      return "Failed to parse search response"
    case .caught(let error):
      return nestedUserFriendlyCaughtMessage(error)
    }
  }
}
