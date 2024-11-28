// Copyright Justin Bishop, 2024

import Foundation
import Testing

@testable import PodHaven

@Suite("of DownloadManager tests")
actor DownloadManagerTests {
  private let session: NetworkingMock

  init() {
    session = NetworkingMock()
  }

  @Test("that a single download works successfully")
  func singleSuccessfulDownload() async {
    let downloadManager = DownloadManager(session: session)

    let url = URL(string: "https://example.com/data")!
    let result = await downloadManager.addURL(url).download()
    switch result {
    case .success(let data):
      #expect(data == url.dataRepresentation, "Returned data should match")
    case .failure(let error):
      Issue.record("Expected success, got error: \(error)")
    }
  }

  @Test("that max concurrent downloads is respected")
  func maxConcurrentDownloads() async {
    let maxConcurrentDownloads = 20
    let downloadManager = DownloadManager(
      session: session,
      maxConcurrentDownloads: maxConcurrentDownloads
    )

    let urls = (1...100).map { URL(string: "https://example.com/data\($0)")! }
    var tasks: [DownloadTask] = []
    for url in urls {
      let task = await downloadManager.addURL(url)
      tasks.append(task)
    }
    for task in tasks {
      _ = await task.download()
    }
    #expect(await session.maxActiveRequests == maxConcurrentDownloads)
  }

  @Test("that you can cancel a mid-flight download")
  func cancelActiveDownload() async {
    let downloadManager = DownloadManager(session: session)

    let url = URL(string: "https://example.com/data")!
    await session.set(url, .delay(.seconds(1)))
    let task = await downloadManager.addURL(url)
    Task {
      try await Task.sleep(for: .milliseconds(100))
      await task.cancel()
    }
    let result = await task.download()
    #expect(result == .failure(.cancelled))
  }
}
