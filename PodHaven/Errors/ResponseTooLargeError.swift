// Copyright Justin Bishop, 2026

import Foundation

struct ResponseTooLargeError: Error, LocalizedError, Sendable {
  let byteLimit: Int
  let responseURL: URL

  var errorDescription: String? {
    """
    The response from \(responseURL.absoluteString) is larger than \
    \(Int64(byteLimit).formatted(.byteCount(style: .memory))).
    """
  }
}
