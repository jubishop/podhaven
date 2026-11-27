// Copyright Justin Bishop, 2026

import Foundation

struct OPMLFileTooLargeError: Error, LocalizedError, Sendable {
  let byteLimit: Int
  let fileName: String

  var errorDescription: String? {
    """
    “\(fileName)” is larger than \(Int64(byteLimit).formatted(.byteCount(style: .memory))), \
    the largest OPML file PodHaven can import.
    """
  }
}
