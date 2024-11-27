// Copyright Justin Bishop, 2024

import Foundation
import Testing

@testable import PodHaven

@Suite("of DownloadManager tests")
class DownloadManagerTests {
  private let session: URLSession

  init() {
    MockURLProtocol.reset()
    
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [MockURLProtocol.self]
    session = URLSession(configuration: configuration)
  }

  @Test("that a single download works successfully")
  func singleSuccessfulDownload() async {
    let url = URL(string: "https://example.com/data")!
    let downloadManager = DownloadManager(
      session: session,
      maxConcurrentDownloads: 2
    )

    let result = await downloadManager.addURL(url).download()
    switch result {
    case .success(let data):
      #expect(data == url.dataRepresentation, "Returned data should match")
    case .failure(let error):
      Issue.record("Expected success, got error: \(error)")
    }
  }
}
