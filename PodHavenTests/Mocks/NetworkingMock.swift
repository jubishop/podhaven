// Copyright Justin Bishop, 2024

import Foundation
import Testing

@testable import PodHaven

enum MockResponse {
  case delay(Duration)
  case data(Data)
  case detail(delay: Duration, data: Data)
  case error(Error)
}

actor NetworkingMock: Networking {
  private var mockResponses: [URL: MockResponse] = [:]
  private(set) var activeRequests = 0
  private(set) var maxActiveRequests = 0

  func data(
    from url: URL,
    delegate: URLSessionTaskDelegate?
  ) async throws -> (Data, URLResponse) {
    defer { activeRequests -= 1 }
    activeRequests += 1
    maxActiveRequests = max(maxActiveRequests, activeRequests)

    switch get(url) {
    case .delay(let delay):
      try await Task.sleep(for: delay)
      return (url.dataRepresentation, response(url))

    case .data(let data):
      return (data, response(url))

    case .detail(let delay, let data):
      try await Task.sleep(for: delay)
      return (data, response(url))

    case .error(let error):
      throw error

    case .none:
      fatalError("No mockResponse for \(url) somehow?")
    }
  }

  func set(_ url: URL, _ response: MockResponse) {
    mockResponses[url] = response
  }

  // MARK: - Private Methods

  private func get(_ url: URL) -> MockResponse? {
    mockResponses[
      url,
      default: .detail(delay: .zero, data: url.dataRepresentation)
    ]
  }

  private func response(_ url: URL, statusCode: Int = 200) -> HTTPURLResponse {
    HTTPURLResponse(
      url: url,
      statusCode: statusCode,
      httpVersion: nil,
      headerFields: [:]
    )!
  }
}
