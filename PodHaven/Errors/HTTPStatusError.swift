// Copyright Justin Bishop, 2026

import Foundation

struct HTTPStatusError: Error, LocalizedError, Sendable {
  let statusCode: Int
  let responseURL: URL

  var errorDescription: String? {
    "The server returned HTTP \(statusCode) for \(responseURL.absoluteString)."
  }
}
