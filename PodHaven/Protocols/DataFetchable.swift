// Copyright Justin Bishop, 2025

import Foundation

protocol DataFetchable: Sendable {
  func data(from url: URL) async throws -> (Data, URLResponse)
  func data(for: URLRequest) async throws -> (Data, URLResponse)
  func validatedData(from url: URL) async throws(DownloadError) -> Data
  func validatedData(for request: URLRequest) async throws(DownloadError) -> Data
}

extension URLSession: DataFetchable {}
