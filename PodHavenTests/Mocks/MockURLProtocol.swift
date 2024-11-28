// Copyright Justin Bishop, 2024

import Foundation
import Testing

enum MockResponse {
  case delay(Duration)
  case data(Data)
  case detail(delay: Duration, data: Data)
  case error(Error)
}

final class MockURLProtocol: URLProtocol {
  private static var mockResponses: [URL: MockResponse] = [:]
  static subscript(url: URL) -> MockResponse? {
    get { mockResponses[url] }
    set { mockResponses[url] = newValue }
  }
  static var activeRequestCount = 0
  static var maxActiveRequestsObserved = 0
  static func reset() {
    mockResponses.removeAll()
    activeRequestCount = 0
    maxActiveRequestsObserved = 0
  }

  override class func canInit(with request: URLRequest) -> Bool {
    true
  }
  override class func canonicalRequest(for request: URLRequest) -> URLRequest {
    request
  }

  override func startLoading() {
    guard let url = request.url, let client = client else {
      fatalError("startLoading has no url or client?!")
    }

    MockURLProtocol.activeRequestCount += 1
    MockURLProtocol.maxActiveRequestsObserved = max(
      MockURLProtocol.maxActiveRequestsObserved,
      MockURLProtocol.activeRequestCount
    )

    let mockDetail =
      MockURLProtocol[url]
      ?? .detail(delay: .zero, data: url.dataRepresentation)

    Task {
      switch mockDetail {
        case .delay(let delay):
          handleResponse(with: url.dataRepresentation, delay: delay)
          
        case .data(let data):
          handleResponse(with: data, delay: .zero)
          
        case .detail(let delay, let data):
          handleResponse(with: data, delay: delay)
          
        case .error(let error):
          client.urlProtocol(self, didFailWithError: error)
      }
      MockURLProtocol.activeRequestCount -= 1
    }
  }

  private func handleResponse(
    with data: Data,
    delay: Duration
  ) {
    guard let url = request.url, let client = client else {
      return
    }
    let response = HTTPURLResponse(
      url: url,
      statusCode: 200,
      httpVersion: nil,
      headerFields: nil
    )!
    if delay > .zero {
      Thread.sleep(for: delay)
    }
    client.urlProtocol(
      self,
      didReceive: response,
      cacheStoragePolicy: .notAllowed
    )
    client.urlProtocol(self, didLoad: data)
    client.urlProtocolDidFinishLoading(self)
  }

  override func stopLoading() {}
}
