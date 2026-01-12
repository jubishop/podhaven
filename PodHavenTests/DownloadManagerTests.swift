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
    var asyncSemaphores: [AsyncSemaphore] = []
    var tasks: [DownloadTask] = []

    for url in urls {
      let asyncSemaphore = await session.waitRespond(to: url)
      let task = await downloadManager.addURL(url)
      asyncSemaphores.append(asyncSemaphore)
      tasks.append(task)
    }

    // Wait for all downloads to complete
    for asyncSemaphore in asyncSemaphores {
      asyncSemaphore.signal()
    }
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
    _ = await session.waitRespond(to: url)
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
    _ = await session.waitRespond(to: url)
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
    _ = await session.waitRespond(to: url)
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

  @Test("that you can call downloadFinished() multiple times before completion")
  func multipleDownloadsCalls() async throws {
    let downloadManager = DownloadManager(session: session)

    let url = URL.valid()
    let asyncSemaphore = await session.waitRespond(to: url)
    let task = await downloadManager.addURL(url)
    let taskCount = 5
    let downloadCount = Counter()
    for _ in 0..<taskCount {
      Task {
        let downloadData = try await task.downloadFinished()
        #expect(downloadData == DownloadData(url: url))
        await downloadCount.increment()
      }
    }
    asyncSemaphore.signal()

    try await downloadCount.wait(for: 5)
    #expect(await downloadCount.value == 5)
  }

  @Test("that urls are downloaded in the order they are requested")
  func urlsDownloadedInOrderRequested() async throws {
    let downloadManager = DownloadManager(
      session: session,
      maxConcurrentDownloads: 1
    )

    // blockingURL will be active (blocking the queue)
    let blockingURL = URL.valid()
    let asyncSemaphore = await session.waitRespond(to: blockingURL)
    _ = await downloadManager.addURL(blockingURL)

    // Add several URLs to the pending queue
    let url1 = URL.valid()
    let url2 = URL.valid()
    let url3 = URL.valid()
    _ = await downloadManager.addURL(url1)
    _ = await downloadManager.addURL(url2)
    _ = await downloadManager.addURL(url3)

    // Unblock original request
    asyncSemaphore.signal()

    try await Wait.until(
      { await session.requests.count >= 4 },
      { "Expected 4 requests, got \(await session.requests.count)" }
    )
    #expect(await session.requests == [blockingURL, url1, url2, url3])
  }

  @Test("that calling addURL on an already pending URL returns same task")
  func callingAddURLOnAlreadyPendingURLReturnsSameTask() async throws {
    let downloadManager = DownloadManager(
      session: session,
      maxConcurrentDownloads: 1
    )

    // blockingURL will be active (blocking the queue)
    let blockingURL = URL.valid()
    _ = await session.waitRespond(to: blockingURL)
    _ = await downloadManager.addURL(blockingURL)

    // url1 task will remain pending
    let url1 = URL.valid()
    let url1Task = await downloadManager.addURL(url1)
    let url1TaskRefetched = await downloadManager.addURL(url1)
    #expect(url1Task.id == url1TaskRefetched.id)
  }

  @Test("that hasURL returns accurately")
  func hasURLReturnsAccurately() async throws {
    let downloadManager = DownloadManager(session: session)

    let url = URL.valid()
    let asyncSemaphore = await session.waitRespond(to: url)
    let downloadTask = await downloadManager.addURL(url)
    #expect(await downloadManager.hasURL(url))

    asyncSemaphore.signal()
    _ = try await downloadTask.downloadFinished()
    #expect(!(await downloadManager.hasURL(url)))
  }

  @Test("that as long as a task exists the Manager won't deallocate")
  func managerDoesNotDeallocate() async throws {
    let url2 = URL.valid()

    func makeTask() async -> (AsyncSemaphore, DownloadTask) {
      let downloadManager = DownloadManager(session: session, maxConcurrentDownloads: 1)
      let url = URL.valid()
      let asyncSemaphore = await session.waitRespond(to: url)
      _ = await downloadManager.addURL(url)
      let downloadTask = await downloadManager.addURL(url2)
      return (asyncSemaphore, downloadTask)
    }
    let (asyncSemaphore, downloadTask) = await makeTask()

    // In theory, the downloadManager could be deallocated now, since it was
    // created inside makeTask().  And since it had to wait for the first
    // url to finish (maxConcurrentDownloads == 1), it would've never
    // actually start()'d the second downloadTask.
    asyncSemaphore.signal()
    let downloadData = try await downloadTask.downloadFinished()
    #expect(downloadData == DownloadData(url: url2))
  }

  // MARK: - Download Failure Tests

  @Test("that network errors are propagated as caught errors")
  func networkErrorIsPropagated() async throws {
    let downloadManager = DownloadManager(session: session)

    let url = URL.valid()
    let networkError = URLError(.notConnectedToInternet)
    await session.respond(to: url, error: networkError)

    let downloadTask = await downloadManager.addURL(url)

    await #expect(throws: DownloadError.caught(networkError)) {
      try await downloadTask.downloadFinished()
    }
    #expect(await downloadTask.finished)
  }

  @Test("that 404 response codes are propagated")
  func notFoundErrorIsPropagated() async throws {
    let downloadManager = DownloadManager(session: session)

    let url = URL.valid()
    await session.respond(to: url) { url in
      let response = HTTPURLResponse(
        url: url,
        statusCode: 404,
        httpVersion: nil,
        headerFields: nil
      )!
      return (Data(), response)
    }

    let downloadTask = await downloadManager.addURL(url)

    await #expect(throws: DownloadError.notOKResponseCode(code: 404, url: url)) {
      try await downloadTask.downloadFinished()
    }
    #expect(await downloadTask.finished)
  }

  @Test("that 500 server errors are propagated")
  func serverErrorIsPropagated() async throws {
    let downloadManager = DownloadManager(session: session)

    let url = URL.valid()
    await session.respond(to: url) { url in
      let response = HTTPURLResponse(
        url: url,
        statusCode: 500,
        httpVersion: nil,
        headerFields: nil
      )!
      return (Data(), response)
    }

    let downloadTask = await downloadManager.addURL(url)

    await #expect(throws: DownloadError.notOKResponseCode(code: 500, url: url)) {
      try await downloadTask.downloadFinished()
    }
    #expect(await downloadTask.finished)
  }

  @Test("that timeout errors are propagated")
  func timeoutErrorIsPropagated() async throws {
    let downloadManager = DownloadManager(session: session)

    let url = URL.valid()
    let timeoutError = URLError(.timedOut)
    await session.respond(to: url, error: timeoutError)

    let downloadTask = await downloadManager.addURL(url)

    await #expect(throws: DownloadError.caught(timeoutError)) {
      try await downloadTask.downloadFinished()
    }
    #expect(await downloadTask.finished)
  }

  @Test("that failed downloads don't block subsequent downloads")
  func failedDownloadDoesNotBlockQueue() async throws {
    let downloadManager = DownloadManager(session: session, maxConcurrentDownloads: 1)

    // First URL will fail
    let failingURL = URL.valid()
    await session.respond(to: failingURL, error: URLError(.notConnectedToInternet))
    let failingTask = await downloadManager.addURL(failingURL)

    // Second URL should succeed after first fails
    let successURL = URL.valid()
    let successTask = await downloadManager.addURL(successURL)

    // Wait for both to complete
    await #expect(throws: DownloadError.self) {
      try await failingTask.downloadFinished()
    }

    let successData = try await successTask.downloadFinished()
    #expect(successData == DownloadData(url: successURL))
  }

  @Test("that multiple failures are handled correctly")
  func multipleFailuresHandledCorrectly() async throws {
    let downloadManager = DownloadManager(session: session)

    let urls = (1...3).map { URL(string: "https://example.com/fail\($0)")! }

    // Set up different failure types
    await session.respond(to: urls[0], error: URLError(.notConnectedToInternet))
    await session.respond(to: urls[1]) { url in
      let response = HTTPURLResponse(
        url: url,
        statusCode: 404,
        httpVersion: nil,
        headerFields: nil
      )!
      return (Data(), response)
    }
    await session.respond(to: urls[2], error: URLError(.timedOut))

    let tasks = await urls.asyncMap { await downloadManager.addURL($0) }

    await #expect(throws: DownloadError.caught(URLError(.notConnectedToInternet))) {
      try await tasks[0].downloadFinished()
    }
    await #expect(throws: DownloadError.notOKResponseCode(code: 404, url: urls[1])) {
      try await tasks[1].downloadFinished()
    }
    await #expect(throws: DownloadError.caught(URLError(.timedOut))) {
      try await tasks[2].downloadFinished()
    }
  }

  @Test("that calling downloadFinished() multiple times after failure returns same error")
  func multipleCallsAfterFailureReturnSameError() async throws {
    let downloadManager = DownloadManager(session: session)

    let url = URL.valid()
    let networkError = URLError(.notConnectedToInternet)
    await session.respond(to: url, error: networkError)

    let downloadTask = await downloadManager.addURL(url)

    // First call should throw
    await #expect(throws: DownloadError.caught(networkError)) {
      try await downloadTask.downloadFinished()
    }

    // Second call should throw the same error
    await #expect(throws: DownloadError.caught(networkError)) {
      try await downloadTask.downloadFinished()
    }

    // Third call should still throw the same error
    await #expect(throws: DownloadError.caught(networkError)) {
      try await downloadTask.downloadFinished()
    }
  }

  @Test("that delayed failure is properly handled")
  func delayedFailureIsHandled() async throws {
    let downloadManager = DownloadManager(session: session)

    let url = URL.valid()
    let networkError = URLError(.networkConnectionLost)
    let asyncSemaphore = await session.waitRespond(to: url, error: networkError)

    let downloadTask = await downloadManager.addURL(url)

    // Set up waiters before releasing the semaphore
    let errorCount = Counter()
    for _ in 0..<3 {
      Task {
        do {
          _ = try await downloadTask.downloadFinished()
        } catch {
          await errorCount.increment()
        }
      }
    }

    // Release the semaphore to trigger the error
    asyncSemaphore.signal()

    try await errorCount.wait(for: 3)
    #expect(await errorCount.value == 3)
  }
}
