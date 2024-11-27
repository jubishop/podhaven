// Copyright Justin Bishop, 2024

import Foundation
import Testing

final class MockURLProtocol: URLProtocol {
  struct URLDetail: Sendable {
    let data: Data?
    let delay: Duration?

    init(data: Data? = nil, delay: Duration? = nil) {
      self.data = data
      self.delay = delay
    }
  }
  static var urlDetails: [URL: URLDetail] = [:]
  static func reset() {
    urlDetails.removeAll()
  }

  override class func canInit(with request: URLRequest) -> Bool {
    true
  }

  override class func canonicalRequest(for request: URLRequest) -> URLRequest {
    request
  }

  override func startLoading() {
    do {
      let urlDetail = MockURLProtocol.urlDetails[
        request.url!,
        default: URLDetail()
      ]
      let response = try #require(
        HTTPURLResponse(
          url: request.url!,
          statusCode: 200,
          httpVersion: nil,
          headerFields: nil
        )
      )
      let data = urlDetail.data ?? request.url!.dataRepresentation
      if let delay = urlDetail.delay {
        Thread.sleep(for: delay)
      }
      client?
        .urlProtocol(
          self,
          didReceive: response,
          cacheStoragePolicy: .notAllowed
        )
      client?.urlProtocol(self, didLoad: data)
      client?.urlProtocolDidFinishLoading(self)
    } catch {
      client?.urlProtocol(self, didFailWithError: error)
    }
  }

  override func stopLoading() {}
}
