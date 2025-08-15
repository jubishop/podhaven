#if DEBUG
// Copyright Justin Bishop, 2025

import Foundation

extension URL {
  static func valid() -> URL {
    URL(string: "https://www.valid.com/\(String.random())")!
  }

  static func response(_ url: URL, statusCode: Int = 200) -> HTTPURLResponse {
    HTTPURLResponse(
      url: url,
      statusCode: statusCode,
      httpVersion: nil,
      headerFields: [:]
    )!
  }
}
#endif
