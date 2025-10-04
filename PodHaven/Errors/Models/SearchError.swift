// Copyright Justin Bishop, 2025

import Foundation
import ReadableErrorMacro

@ReadableError
enum SearchError: ReadableError {
  case fetchFailure(request: URLRequest, caught: Error)
  case parseFailure(data: Data, caught: Error)

  var message: String {
    switch self {
    case .fetchFailure(let request, _):
      return "Failed to fetch url: \(request)"
    case .parseFailure(let data, _):
      return "Failed to parse data: \(String(decoding: data, as: UTF8.self))"
    }
  }
}
