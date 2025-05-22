// Copyright Justin Bishop, 2025

import Foundation
import ReadableErrorMacro

@ReadableError
enum SearchError: ReadableError {
  case fetchFailure(request: URLRequest, caught: Error)
  case parseFailure(Data)

  var message: String {
    switch self {
    case .fetchFailure(let request, _):
      return "Failed to fetch url: \(request)"
    case .parseFailure:
      return "Failed to parse search response"
    }
  }
}
