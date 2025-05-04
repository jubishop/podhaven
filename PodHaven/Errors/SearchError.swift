// Copyright Justin Bishop, 2025

import ErrorKit
import Foundation

enum SearchError: KittedError {
  case fetchFailure(request: URLRequest, networkError: NetworkError)
  case parseFailure(Data)
  case caught(Error)

  var nestableUserFriendlyMessage: String {
    switch self {
    case .fetchFailure(let request, let networkError):
      return
        """
        Failed to fetch url: \(request) ->
          \(Self.userFriendlyMessage(for: networkError))
        """
    case .parseFailure:
      return "Failed to parse search response"
    case .caught(let error):
      return userFriendlyCaughtMessage(caught: error)
    }
  }
}
