// Copyright Justin Bishop, 2024

import Foundation
import Testing

@testable import PodHaven

struct DownloadManagerTests {
  @Test("A single download works successfully")
  static func singleSuccessfulDownload() async throws {
    let url = URL(string: "https://example.com/data")!
    let expectedData = "Test data".data(using: .utf8)!

    MockURLProtocol.requestHandler = { request in
      #expect(request.url == url)
      let response = try #require(
        HTTPURLResponse(
          url: url,
          statusCode: 200,
          httpVersion: nil,
          headerFields: nil
        )
      )
      return (response, expectedData)
    }

    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [MockURLProtocol.self]
    let session = URLSession(configuration: configuration)
    let downloadManager = DownloadManager(
      session: session,
      maxConcurrentDownloads: 2
    )

    await expectation("Single download handler is called") { fulfillment in
      await downloadManager.addURL(url) { result in
        switch result {
        case .success(let data):
          #expect(data == expectedData)
          fulfillment()
        case .failure(let error):
          Issue.record("Expected success, got error: \(error)")
        }
      }
    }
  }
}
