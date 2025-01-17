// Copyright Justin Bishop, 2025

import Foundation
import Testing

@testable import PodHaven

enum MockResponse {
  case delay(Duration)
  case data(Data)
  case detail(delay: Duration, data: Data)
  case error(Error)
  case production
}

final actor DataFetchableMock: DataFetchable {
  private let session: URLSession
  private var mockResponses: [URL: MockResponse] = [:]
  private(set) var requests: [URL] = []
  private(set) var activeRequests = 0
  private(set) var maxActiveRequests = 0

  init(session: URLSession = URLSession.shared) {
    self.session = session
  }

  func data(for urlRequest: URLRequest) async throws -> (Data, URLResponse) {
    guard let url = urlRequest.url else { fatalError("No URL in URLRequest: \(urlRequest)??") }

    activeRequests += 1
    defer { activeRequests -= 1 }
    maxActiveRequests = max(maxActiveRequests, activeRequests)
    requests.append(url)

    switch get(url) {
    case .production:
      return try await session.data(for: urlRequest)

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
    }
  }

  func data(from url: URL) async throws -> (Data, URLResponse) {
    try await data(for: URLRequest(url: url))
  }

  func set(_ url: URL, _ response: MockResponse) {
    mockResponses[url] = response
  }

  // MARK: - Private Methods

  private func get(_ url: URL) -> MockResponse {
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
