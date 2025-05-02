// Copyright Justin Bishop, 2025

import ErrorKit
import Foundation

enum SearchError: KittedError {
  case termFailure(String)
  case titleFailure(String)
  case personFailure(String)
  case trendingFailure([String])
  case fetchFailure(request: URLRequest, networkError: NetworkError)
  case parseFailure(Data)
  case caught(Error)

  var userFriendlyMessage: String {
    switch self {
    case .termFailure(let term):
      return "Failed to search for term: \(term)"
    case .titleFailure(let title):
      return "Failed to search for title: \(title)"
    case .personFailure(let name):
      return "Failed to search for person: \(name)"
    case .trendingFailure(let categories):
      return "Failed to search for trending categories: \(categories.joined(separator: ", "))"
    case .fetchFailure(let request, let networkError):
      return
        """
        Failed to fetch URL
          Request URL: \(request)
          Network Error: \(ErrorKit.userFriendlyMessage(for: networkError))
        """
    case .parseFailure:
      return "Failed to parse search response"
    case .caught(let error):
      return ErrorKit.userFriendlyMessage(for: error)
    }
  }
}
