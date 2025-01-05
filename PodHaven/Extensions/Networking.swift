// Copyright Justin Bishop, 2025

import Foundation

protocol Networking: Sendable {
  func data(from url: URL) async throws -> (Data, URLResponse)
  func data(for: URLRequest) async throws -> (Data, URLResponse)
}

extension URLSession: Networking {}
