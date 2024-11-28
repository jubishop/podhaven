// Copyright Justin Bishop, 2024

import Foundation

protocol Networking {
  func data(
    from url: URL,
    delegate: (any URLSessionTaskDelegate)?
  ) async throws -> (Data, URLResponse)
}

extension Networking {
  func data(from url: URL) async throws -> (Data, URLResponse) {
    try await data(from: url, delegate: nil)
  }
}

extension URLSession: Networking {}
