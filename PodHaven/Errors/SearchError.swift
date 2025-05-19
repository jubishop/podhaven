// Copyright Justin Bishop, 2025

import Foundation
import ReadableErrorMacro

@ReadableError
enum SearchError: ReadableError {
  case fetchFailure(request: URLRequest, caught: Error)
  case parseFailure(Data)

  var message: String {
    switch self {
    case .fetchFailure(let request, let error):
      return
        """
        Failed to fetch url: \(request) ->
        \(ErrorKit.nestedCaughtMessage(for: error))
        """
    case .parseFailure:
      return "Failed to parse search response"
    }
  }
}
