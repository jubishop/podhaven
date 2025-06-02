// Copyright Justin Bishop, 2025

import Foundation
import Semaphore
import Testing

@testable import PodHaven

actor FakeDataFetchable: DataFetchable {
  private let session: URLSession
  private var fakeHandlers: [URL: @Sendable (URL) async throws -> (Data, URLResponse)] = [:]
  private(set) var requests: [URL] = []
  private(set) var activeRequests = 0
  private(set) var maxActiveRequests = 0

  init(session: URLSession = URLSession.shared) {
    self.session = session
  }

  func data(for urlRequest: URLRequest) async throws -> (Data, URLResponse) {
    guard let url = urlRequest.url
    else { Assert.fatal("No URL in URLRequest: \(urlRequest)??") }

    activeRequests += 1
    defer { activeRequests -= 1 }
    maxActiveRequests = max(maxActiveRequests, activeRequests)
    requests.append(url)

    if let handler = fakeHandlers[url] {
      return try await handler(url)
    }

    // Default fallback behavior if no handler is set
    return (url.dataRepresentation, URL.response(url))
  }

  func data(from url: URL) async throws -> (Data, URLResponse) {
    try await data(for: URLRequest(url: url))
  }

  func respond(
    to url: URL,
    with handler: @Sendable @escaping (URL) async throws -> (Data, URLResponse)
  ) {
    fakeHandlers[url] = handler
  }

  // Convenience methods for common test patterns
  func respondWithData(to url: URL, data: Data) {
    respond(to: url) { url in
      (data, URL.response(url))
    }
  }

  func respondWithDelay(to url: URL, delay: Duration) {
    respond(to: url) { url in
      try await Task.sleep(for: delay)
      return (url.dataRepresentation, URL.response(url))
    }
  }

  func respondWithError(to url: URL, error: Error) {
    respond(to: url) { _ in
      throw error
    }
  }
}
