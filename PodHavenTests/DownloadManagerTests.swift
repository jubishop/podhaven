// Copyright Justin Bishop, 2024

import Foundation
import Testing

@testable import PodHaven

@Suite("of DownloadManager tests")
class DownloadManagerTests {
  @Test("that a single download works successfully")
  func singleSuccessfulDownload() async {
    let url = URL(string: "https://example.com/data")!
    let expectedData = "Test data".data(using: .utf8)!

    MockURLProtocol.requestHandler = { request in
      #expect(request.url == url, "URL Requested should be what was added")
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

    let fulfilled = Fulfillment()
    await downloadManager.addURL(url) { result in
      switch result {
        case .success(let data):
          #expect(data == expectedData, "Returned data should match")
          await fulfilled()
        case .failure(let error):
          Issue.record("Expected success, got error: \(error)")
      }
    }
    await expect("Try one", is: fulfilled)
    
    await expect("Single download handler") { fulfilled in
      await downloadManager.addURL(url) { result in
        switch result {
        case .success(let data):
          #expect(data == expectedData, "Returned data should match")
          await fulfilled()
        case .failure(let error):
          Issue.record("Expected success, got error: \(error)")
        }
      }
    }
  }
}
