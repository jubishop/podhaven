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
      await session.set(url, .delay(.milliseconds(10)))
      let task = await downloadManager.addURL(url)
      tasks.append(task)
    }
    for task in tasks {
      _ = await task.download()
    }
    let maxActiveRequests = await session.maxActiveRequests
    #expect(maxActiveRequests == maxConcurrentDownloads)
  }

  @Test("that you can cancel a mid-flight download")
  func cancelActiveDownload() async throws {
    let downloadManager = DownloadManager(session: session)

    let url = URL(string: "https://example.com/data")!
    await session.set(url, .delay(.milliseconds(50)))
    let task = await downloadManager.addURL(url)
    Task {
      try await Task.sleep(for: .milliseconds(10))
      await task.cancel()
    }
    var result = await task.download()
    #expect(result == .failure(.cancelled))

    // Even after the url data has returned, the result remains cancelled.
    try await Task.sleep(for: .milliseconds(100))
    result = await task.download()
    #expect(result == .failure(.cancelled))
  }

  @Test("that url's are fetched in the order they're received")
  func fetchedInOrder() async throws {
    let downloadManager = DownloadManager(
      session: session,
      // No concurrency, otherwise ordering is impossible to guarantee.
      maxConcurrentDownloads: 1
    )

    let urls = (1...100).map { URL(string: "https://example.com/data\($0)")! }
    var tasks: [DownloadTask] = []
    for url in urls {
      let task = await downloadManager.addURL(url)
      tasks.append(task)
    }
    // Reversed download awaits, ensure URL's still downloaded in order.
    for task in tasks.reversed() {
      _ = await task.download()
    }
    let requests = await session.requests
    #expect(requests == urls)
  }

  @Test("that you can call download() multiple times before completion")
  func multipleDownloadsCalls() async throws {
    let downloadManager = DownloadManager(session: session)

    let url = URL(string: "https://example.com/data")!
    await session.set(url, .delay(.milliseconds(500)))
    let task = await downloadManager.addURL(url)
    let downloadCount = Counter()
    let taskCount = 5
    for _ in 0..<taskCount {
      Task {
        let result = await task.download()
        switch result {
        case .success(let data):
          #expect(data == url.dataRepresentation, "Returned data should match")
          await downloadCount.increment()
        case .failure(let error):
          Issue.record("Expected success, got error: \(error)")
        }
      }
    }
    try await Task.sleep(for: .seconds(1))
    let tally = await downloadCount.counter
    #expect(tally == taskCount)
  }
}
