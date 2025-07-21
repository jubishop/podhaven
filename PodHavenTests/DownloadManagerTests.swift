// Copyright Justin Bishop, 2025

import Foundation
import Semaphore
import Testing

@testable import PodHaven

@Suite("of DownloadManager tests", .container)
struct DownloadManagerTests {
  private let session: FakeDataFetchable

  init() {
    session = FakeDataFetchable()
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

  @Test("that maxConcurrentDownloads is respected")
  func maxConcurrentDownloads() async throws {
    let maxConcurrentDownloads = 20
    let downloadManager = DownloadManager(
      session: session,
      maxConcurrentDownloads: maxConcurrentDownloads
    )

    // Add enough urls to ensure we hit our max concurrency
    let urls = (1...100).map { URL(string: "https://example.com/data\($0)")! }
    var tasks: [DownloadTask] = []

    // Set all URLs to have a measurable delay to ensure we observe max concurrency
    for url in urls {
      await session.respond(to: url, delay: .milliseconds(10))
      let task = await downloadManager.addURL(url)
      tasks.append(task)
    }

    // Wait for all downloads to complete
    for task in tasks {
      _ = try? await task.downloadFinished()
    }

    // The mock's maxActiveRequests property tracks the highest concurrency observed
    let observedMax = await session.maxActiveRequests

    // Verify the download manager respected the max concurrent downloads limit
    #expect(
      observedMax == maxConcurrentDownloads,
      "Expected max of \(maxConcurrentDownloads) concurrent downloads, observed \(observedMax)"
    )
  }

  @Test("that you can cancel a download before it has begun")
  func cancelPendingDownload() async throws {
    let downloadManager = DownloadManager(session: session, maxConcurrentDownloads: 1)

    // Since maxConcurrentDownloads is 1 this task holds up the queue
    let url = URL.valid()
    await session.respond(to: url, delay: .milliseconds(500))
    _ = await downloadManager.addURL(url)

    // This task is stuck waiting on the first url
    let url2 = URL.valid()
    let task2 = await downloadManager.addURL(url2)

    // This task has had no chance to begin yet
    await task2.cancel()
    await #expect(throws: DownloadError.cancelled(url2)) {
      try await task2.downloadFinished()
    }
  }

  @Test("that you can cancel a mid-flight download")
  func cancelActiveDownload() async throws {
    let downloadManager = DownloadManager(session: session)

    let url = URL.valid()
    await session.respond(to: url, delay: .milliseconds(50))
    let task = await downloadManager.addURL(url)

    // Cancels the task, not immediately but before it is done
    Task {
      await task.downloadBegan()
      await task.cancel()
    }

    // Task throws cancelled after being cancelled mid-flight
    await #expect(throws: DownloadError.cancelled(url)) {
      try await task.downloadFinished()
    }

    // The result always remains cancelled.
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
    await session.respond(to: url, delay: .milliseconds(50))
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

    // The results always remain cancelled.
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
    await session.respond(to: url, delay: .milliseconds(50))
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

    try await downloadCount.waitForExpected()
    #expect(await downloadCount.reachedExpected)
  }

  @Test("that as long as a task exists the Manager won't deallocate")
  func managerDoesNotDeallocate() async throws {
    let url2 = URL.valid()

    func makeTask() async -> DownloadTask {
      let downloadManager = DownloadManager(session: session, maxConcurrentDownloads: 1)
      let url = URL.valid()
      await session.respond(to: url, delay: .milliseconds(100))
      _ = await downloadManager.addURL(url)
      await session.respond(to: url2, delay: .milliseconds(100))
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
}
