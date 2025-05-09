// Copyright Justin Bishop, 2025

import Foundation
import Semaphore
import Testing

@testable import PodHaven

enum MockResponse {
  case delay(Duration)
  case data(Data)
  case detail(delay: Duration, data: Data)
  case error(Error)
  case production(Bool)
  case custom(@Sendable (URL) async throws -> (Data, URLResponse))
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
    guard let url = urlRequest.url
    else { Log.fatal("No URL in URLRequest: \(urlRequest)??") }

    activeRequests += 1
    defer { activeRequests -= 1 }
    maxActiveRequests = max(maxActiveRequests, activeRequests)
    requests.append(url)

    switch get(url) {
    case .production(let printData):
      let (data, response) = try await session.data(for: urlRequest)
      if printData {
        Log.debug("Response for: \(url)")
        Log.debug("URLResponse: \(response)")
        Log.debug("Data: \(String(data: data, encoding: .utf8) ?? "No Data")")
      }
      return (data, response)

    case .delay(let delay):
      try await Task.sleep(for: delay)
      return (url.dataRepresentation, URL.response(url))

    case .data(let data):
      return (data, URL.response(url))

    case .detail(let delay, let data):
      try await Task.sleep(for: delay)
      return (data, URL.response(url))

    case .error(let error):
      throw error

    case .custom(let closure):
      return try await closure(url)
    }
  }

  func data(from url: URL) async throws -> (Data, URLResponse) {
    try await data(for: URLRequest(url: url))
  }

  func set(_ url: URL, _ response: MockResponse) {
    mockResponses[url] = response
  }

  // MARK: - Private Helpers

  private func get(_ url: URL) -> MockResponse {
    mockResponses[
      url,
      default: .detail(delay: .zero, data: url.dataRepresentation)
    ]
  }
}
