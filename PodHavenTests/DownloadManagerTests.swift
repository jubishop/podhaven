// Copyright Justin Bishop, 2025

import Foundation
import Semaphore
import Testing

@testable import PodHaven

@Suite("of DownloadManager tests")
struct DownloadManagerTests {
  private let session: DataFetchableMock

  init() {
    session = DataFetchableMock()
  }

  @Test("that a single download works successfully")
  func singleSuccessfulDownload() async throws {
    let downloadManager = DownloadManager(session: session)

    let url = URL.valid()
    let downloadTask = await downloadManager.addURL(url)
    let downloadData = try await downloadTask.downloadFinished()
    #expect(downloadData == DownloadData(url: url))
    #expect(await downloadTask.finished)
  }

  @Test("that an array of downloads work successfully")
  func arrayOfSuccessfulDownloads() async throws {
    let downloadManager = DownloadManager(session: session)

    let urls = (1...100).map { URL(string: "https://example.com/data\($0)")! }
    let downloadTasks = await downloadManager.addURLs(urls)
    var results = [DownloadData](capacity: urls.count)
    for downloadTask in downloadTasks {
      results.append(try await downloadTask.downloadFinished())
    }
    #expect(results.count == urls.count)
  }

  @Test("that maxConcurrentDownloads is respected and downloadBegan() works")
  func maxConcurrentDownloads() async throws {
    let maxConcurrentDownloads = 20
    let downloadManager = DownloadManager(
      session: session,
      maxConcurrentDownloads: maxConcurrentDownloads
    )

    // Use a longer delay to ensure stable observation
    let downloadDelay = Duration.milliseconds(500)
    let urls = (1...100).map { URL(string: "https://example.com/data\($0)")! }
    var tasks: [DownloadTask] = []

    for url in urls {
      await session.set(url, .delay(downloadDelay))
      let task = await downloadManager.addURL(url)
      tasks.append(task)
    }

    let activeDownloads = Counter()
    let taskStarted = AsyncSemaphore(value: 0)

    // Create a controlled environment for observation
    try await withThrowingDiscardingTaskGroup { group in
      for task in tasks {
        group.addTask {
          await task.downloadBegan()
          await activeDownloads.increment()
          taskStarted.signal()

          _ = try await task.downloadFinished()
          await activeDownloads.decrement()
        }
      }

      // Wait for enough tasks to start
      for _ in 1...maxConcurrentDownloads + 5 {
        await taskStarted.wait()
      }

      // Give time for download manager to enforce limits
      try? await Task.sleep(for: .milliseconds(100))

      // Check active downloads after stabilization
      let concurrent = await activeDownloads.value
      #expect(concurrent == maxConcurrentDownloads)

      // Double-check with multiple observations
      var counts: [Int] = []
      for _ in 1...5 {
        try? await Task.sleep(for: .milliseconds(50))
        counts.append(await activeDownloads.value)
      }

      let allEqual = counts.allSatisfy { $0 == maxConcurrentDownloads }
      #expect(allEqual, "Expected stable count of \(maxConcurrentDownloads), got \(counts)")
    }
  }

  @Test("that you can cancel a mid-flight download")
  func cancelActiveDownload() async throws {
    let downloadManager = DownloadManager(session: session)

    let url = URL.valid()
    await session.set(url, .delay(.milliseconds(50)))
    let task = await downloadManager.addURL(url)
    Task {
      try await Task.sleep(for: .milliseconds(10))
      await task.cancel()
    }

    await #expect(throws: DownloadError.cancelled(url)) {
      try await task.downloadFinished()
    }

    // Even after the url data has returned, the result remains cancelled.
    try await Task.sleep(for: .milliseconds(100))
    await #expect(throws: DownloadError.cancelled(url)) {
      try await task.downloadFinished()
    }
  }

  @Test("that you can cancel all downloads")
  func cancelAllDownloads() async throws {
    let downloadManager = DownloadManager(
      session: session,
      maxConcurrentDownloads: 1
    )

    let url = URL.valid()
    await session.set(url, .delay(.milliseconds(50)))
    let task = await downloadManager.addURL(url)
    let url2 = URL.valid()
    let task2 = await downloadManager.addURL(url2)

    // At this point: task should be active, task2 should be pending
    await downloadManager.cancelAllDownloads()
    await #expect(throws: DownloadError.cancelled(url)) {
      try await task.downloadFinished()
    }
    await #expect(throws: DownloadError.cancelled(url2)) {
      try await task2.downloadFinished()
    }

    // Even after the url data has returned, the results remains cancelled.
    try await Task.sleep(for: .milliseconds(100))
    await #expect(throws: DownloadError.cancelled(url)) {
      try await task.downloadFinished()
    }
    await #expect(throws: DownloadError.cancelled(url2)) {
      try await task2.downloadFinished()
    }
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
      _ = try await task.downloadFinished()
    }
    let requests = await session.requests
    #expect(requests == urls)
  }

  @Test("that you can call downloadFinished() multiple times before completion")
  func multipleDownloadsCalls() async throws {
    let downloadManager = DownloadManager(session: session)

    let url = URL.valid()
    await session.set(url, .delay(.milliseconds(50)))
    let task = await downloadManager.addURL(url)
    let taskCount = 5
    let downloadCount = Counter(expected: taskCount)
    for _ in 0..<taskCount {
      Task {
        let downloadData = try await task.downloadFinished()
        #expect(downloadData == DownloadData(url: url))
        await downloadCount.increment()
      }
    }

    await downloadCount.waitForExpected()
    #expect(await downloadCount.reachedExpected)
  }

  @Test("that as long as a task exists the Manager won't deallocate")
  func managerDoesNotDeallocate() async throws {
    let url2 = URL.valid()
    func makeTask() async -> DownloadTask {
      let downloadManager = DownloadManager(
        session: session,
        maxConcurrentDownloads: 1
      )
      let url = URL.valid()
      await session.set(url, .delay(.milliseconds(100)))
      _ = await downloadManager.addURL(url)
      await session.set(url2, .delay(.milliseconds(100)))
      return await downloadManager.addURL(url2)
    }
    let task = await makeTask()
    // In theory, the downloadManager could be deallocated now, since it was
    // created inside makeTask().  And since it had to wait for the first
    // url to finish (concurrentTasks = 1, delay = 100ms), it would've never
    // actually start()'d the second downloadTask.
    let downloadData = try await task.downloadFinished()
    #expect(downloadData == DownloadData(url: url2))
  }

  @Test("that you can use the AsyncStream to get results")
  func basicAsyncStream() async throws {
    let downloadManager = DownloadManager(session: session)

    let urls = (1...100).map { URL(string: "https://example.com/data\($0)")! }
    for url in urls {
      await downloadManager.addURL(url)
    }
    var resultsReceived = 0
    for await result in await downloadManager.downloads() {
      #expect(result.isSuccessful())
      resultsReceived += 1
      if resultsReceived == 100 {
        break
      }
    }
  }
}
