// Copyright Justin Bishop, 2024

import Foundation

enum DownloadError: Error, LocalizedError, Sendable, Equatable {
  case invalidResponse
  case invalidStatusCode(Int)
  case networkError(Error)
  case cancelled

  var errorDescription: String? {
    switch self {
    case .invalidResponse:
      return "Received an invalid response from the server."
    case .invalidStatusCode(let statusCode):
      return "Received HTTP status code \(statusCode)."
    case .networkError(let error):
      return "A network error occurred: \(error.localizedDescription)"
    case .cancelled:
      return "The download was cancelled."
    }
  }

  static func == (lhs: DownloadError, rhs: DownloadError) -> Bool {
    switch (lhs, rhs) {
    case (.invalidResponse, .invalidResponse),
      (.cancelled, .cancelled),
      (.networkError, .networkError):
      return true
    case (.invalidStatusCode(let lhsCode), .invalidStatusCode(let rhsCode)):
      return lhsCode == rhsCode
    default:
      return false
    }
  }
}
