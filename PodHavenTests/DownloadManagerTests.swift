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
      do { _ = try await task.downloadFinished() } catch { /* expected */  }
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
    await #expect(throws: CancellationError.self) {
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
    await #expect(throws: CancellationError.self) {
      try await task.downloadFinished()
    }

    // The result always remains cancelled.
    await #expect(throws: CancellationError.self) {
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
    await #expect(throws: CancellationError.self) {
      try await task.downloadFinished()
    }
    await #expect(throws: CancellationError.self) {
      try await task2.downloadFinished()
    }

    // The results always remain cancelled.
    await #expect(throws: CancellationError.self) {
      try await task.downloadFinished()
    }
    await #expect(throws: CancellationError.self) {
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

  @Test("that network errors are propagated")
  func networkErrorIsPropagated() async throws {
    let downloadManager = DownloadManager(session: session)

    let url = URL.valid()
    let networkError = URLError(.notConnectedToInternet)
    await session.respond(to: url, error: networkError)

    let downloadTask = await downloadManager.addURL(url)

    await #expect(throws: URLError.self) {
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

    await #expect(throws: (any Error).self) {
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

    await #expect(throws: (any Error).self) {
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

    await #expect(throws: URLError.self) {
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
    await #expect(throws: (any Error).self) {
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

    await #expect(throws: URLError.self) {
      try await tasks[0].downloadFinished()
    }
    await #expect(throws: (any Error).self) {
      try await tasks[1].downloadFinished()
    }
    await #expect(throws: URLError.self) {
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
    await #expect(throws: URLError.self) {
      try await downloadTask.downloadFinished()
    }

    // Second call should throw the same error
    await #expect(throws: URLError.self) {
      try await downloadTask.downloadFinished()
    }

    // Third call should still throw the same error
    await #expect(throws: URLError.self) {
      try await downloadTask.downloadFinished()
    }
  }

  // MARK: - Direct DownloadTask.cancel() Tests

  @Test("that direct DownloadTask.cancel() removes a pending task from manager state")
  func directCancelOfPendingRemovesFromManager() async throws {
    let downloadManager = DownloadManager(session: session, maxConcurrentDownloads: 1)

    let blockingURL = URL.valid()
    _ = await session.waitRespond(to: blockingURL)
    _ = await downloadManager.addURL(blockingURL)

    let pendingURL = URL.valid()
    let pendingTask = await downloadManager.addURL(pendingURL)
    #expect(await downloadManager.hasURL(pendingURL))

    await pendingTask.cancel()

    #expect(!(await downloadManager.hasURL(pendingURL)))

    // Subsequent addURL for the same URL must return a fresh, non-finished task,
    // not the already-cancelled wrapper.
    let freshTask = await downloadManager.addURL(pendingURL)
    #expect(!(await freshTask.finished))
    #expect(freshTask !== pendingTask)
  }

  @Test("that direct DownloadTask.cancel() on an active task frees its concurrency slot")
  func directCancelOfActiveFreesSlot() async throws {
    let downloadManager = DownloadManager(session: session, maxConcurrentDownloads: 1)

    let activeURL = URL.valid()
    _ = await session.waitRespond(to: activeURL)
    let activeTask = await downloadManager.addURL(activeURL)
    await activeTask.downloadBegan()

    let nextURL = URL.valid()
    let nextTask = await downloadManager.addURL(nextURL)
    #expect(await downloadManager.hasURL(nextURL))

    await activeTask.cancel()

    #expect(!(await downloadManager.hasURL(activeURL)))

    // Bounded wait so the test fails fast against the unfixed code path
    // where the pending task would otherwise wait on a never-started fetch.
    try await Wait.until(
      { await nextTask.finished },
      { "Expected nextTask to finish after activeTask was directly cancelled" }
    )
    let nextData = try await nextTask.downloadFinished()
    #expect(nextData == DownloadData(url: nextURL))
  }

  @Test("that direct DownloadTask.cancel() cancels the underlying URLSession fetch")
  func directCancelCancelsUnderlyingFetch() async throws {
    let downloadManager = DownloadManager(session: session)

    let url = URL.valid()
    _ = await session.waitRespond(to: url)
    let task = await downloadManager.addURL(url)
    await task.downloadBegan()

    await task.cancel()

    await #expect(throws: CancellationError.self) {
      try await task.downloadFinished()
    }
    try await Wait.until(
      { await session.cancelledRequests.contains(url) },
      { "Expected \(url) in cancelledRequests, got \(await session.cancelledRequests)" }
    )
  }

  @Test("that calling cancel() multiple times on the same task is idempotent")
  func directCancelIsIdempotent() async throws {
    let downloadManager = DownloadManager(session: session)

    let url = URL.valid()
    _ = await session.waitRespond(to: url)
    let task = await downloadManager.addURL(url)
    await task.downloadBegan()

    await task.cancel()
    await task.cancel()
    await task.cancel()

    await #expect(throws: CancellationError.self) {
      try await task.downloadFinished()
    }
    // The underlying fetch should be cancelled exactly once even though
    // cancel() was invoked three times — second/third calls must short-circuit.
    try await Wait.until(
      { await session.cancelledRequests.filter { $0 == url }.count == 1 },
      {
        "Expected \(url) cancelled exactly once, got \(await session.cancelledRequests)"
      }
    )
  }

  @Test("that calling cancel() on a successfully-finished task is a no-op")
  func directCancelAfterSuccessIsNoop() async throws {
    let downloadManager = DownloadManager(session: session)

    let url = URL.valid()
    let task = await downloadManager.addURL(url)
    let data = try await task.downloadFinished()
    #expect(data == DownloadData(url: url))

    await task.cancel()

    let dataAgain = try await task.downloadFinished()
    #expect(dataAgain == DownloadData(url: url))
    #expect(await session.cancelledRequests.isEmpty)
  }

  @Test("that cancelling one task does not affect other concurrent downloads")
  func cancelOneDoesNotAffectConcurrentDownloads() async throws {
    let downloadManager = DownloadManager(session: session, maxConcurrentDownloads: 3)

    let cancelURL = URL.valid()
    let succeedURL1 = URL.valid()
    let succeedURL2 = URL.valid()
    _ = await session.waitRespond(to: cancelURL)  // never signalled

    let cancelTask = await downloadManager.addURL(cancelURL)
    let succeedTask1 = await downloadManager.addURL(succeedURL1)
    let succeedTask2 = await downloadManager.addURL(succeedURL2)

    await cancelTask.downloadBegan()
    await cancelTask.cancel()

    let data1 = try await succeedTask1.downloadFinished()
    let data2 = try await succeedTask2.downloadFinished()
    #expect(data1 == DownloadData(url: succeedURL1))
    #expect(data2 == DownloadData(url: succeedURL2))
    await #expect(throws: CancellationError.self) {
      try await cancelTask.downloadFinished()
    }
  }

  // MARK: - DownloadManager.cancelDownload(url:) Tests

  @Test("that cancelDownload(url:) removes a pending task from manager state")
  func cancelDownloadOfPendingRemovesFromManager() async throws {
    let downloadManager = DownloadManager(session: session, maxConcurrentDownloads: 1)

    let blockingURL = URL.valid()
    _ = await session.waitRespond(to: blockingURL)
    _ = await downloadManager.addURL(blockingURL)

    let pendingURL = URL.valid()
    let pendingTask = await downloadManager.addURL(pendingURL)
    #expect(await downloadManager.hasURL(pendingURL))

    await downloadManager.cancelDownload(url: pendingURL)

    #expect(!(await downloadManager.hasURL(pendingURL)))
    await #expect(throws: CancellationError.self) {
      try await pendingTask.downloadFinished()
    }
  }

  @Test("that cancelDownload(url:) on an active task frees its concurrency slot")
  func cancelDownloadOfActiveFreesSlot() async throws {
    let downloadManager = DownloadManager(session: session, maxConcurrentDownloads: 1)

    let activeURL = URL.valid()
    _ = await session.waitRespond(to: activeURL)
    let activeTask = await downloadManager.addURL(activeURL)
    await activeTask.downloadBegan()

    let nextURL = URL.valid()
    let nextTask = await downloadManager.addURL(nextURL)

    await downloadManager.cancelDownload(url: activeURL)

    #expect(!(await downloadManager.hasURL(activeURL)))
    let nextData = try await nextTask.downloadFinished()
    #expect(nextData == DownloadData(url: nextURL))
    await #expect(throws: CancellationError.self) {
      try await activeTask.downloadFinished()
    }
  }

  @Test("that cancelDownload(url:) cancels the underlying URLSession fetch")
  func cancelDownloadCancelsUnderlyingFetch() async throws {
    let downloadManager = DownloadManager(session: session)

    let url = URL.valid()
    _ = await session.waitRespond(to: url)
    let task = await downloadManager.addURL(url)
    await task.downloadBegan()

    await downloadManager.cancelDownload(url: url)

    await #expect(throws: CancellationError.self) {
      try await task.downloadFinished()
    }
    try await Wait.until(
      { await session.cancelledRequests.contains(url) },
      { "Expected \(url) in cancelledRequests, got \(await session.cancelledRequests)" }
    )
  }

  @Test("that cancelAllDownloads() cancels all in-flight URLSession fetches")
  func cancelAllDownloadsCancelsUnderlyingFetches() async throws {
    let downloadManager = DownloadManager(session: session, maxConcurrentDownloads: 2)

    let url1 = URL.valid()
    let url2 = URL.valid()
    _ = await session.waitRespond(to: url1)
    _ = await session.waitRespond(to: url2)
    let task1 = await downloadManager.addURL(url1)
    let task2 = await downloadManager.addURL(url2)
    await task1.downloadBegan()
    await task2.downloadBegan()

    await downloadManager.cancelAllDownloads()

    await #expect(throws: CancellationError.self) {
      try await task1.downloadFinished()
    }
    await #expect(throws: CancellationError.self) {
      try await task2.downloadFinished()
    }
    try await Wait.until(
      {
        let cancelled = Set(await session.cancelledRequests)
        return cancelled.contains(url1) && cancelled.contains(url2)
      },
      {
        "Expected both URLs in cancelledRequests, got \(await session.cancelledRequests)"
      }
    )
  }

  @Test("that cancelAllDownloads() cancels pending downloads without starting them")
  func cancelAllDownloadsCancelsPendingDownloadsWithoutStartingThem() async throws {
    let maxConcurrentDownloads = 20
    let downloadManager = DownloadManager(
      session: session,
      maxConcurrentDownloads: maxConcurrentDownloads
    )

    let activeURLs = (0..<maxConcurrentDownloads)
      .map { index in
        URL(string: "https://example.com/active-\(index)")!
      }
    let activeTasks = await activeURLs.asyncMap { url in
      _ = await session.waitRespond(to: url)
      return await downloadManager.addURL(url)
    }
    for activeTask in activeTasks {
      await activeTask.downloadBegan()
    }

    let pendingURL = URL.valid()
    let pendingTask = await downloadManager.addURL(pendingURL)
    #expect(await downloadManager.hasURL(pendingURL))
    #expect(!(await session.requests.contains(pendingURL)))

    let cancellationTask = Task(priority: .background) {
      await downloadManager.cancelAllDownloads()
    }
    await cancellationTask.value

    for activeTask in activeTasks {
      await #expect(throws: CancellationError.self) {
        try await activeTask.downloadFinished()
      }
    }
    await #expect(throws: CancellationError.self) {
      try await pendingTask.downloadFinished()
    }
    for activeURL in activeURLs {
      #expect(!(await downloadManager.hasURL(activeURL)))
    }
    #expect(!(await downloadManager.hasURL(pendingURL)))
    #expect(!(await session.requests.contains(pendingURL)))
  }

  // MARK: - addURL Identity Tests

  @Test("that calling addURL on an already active URL returns the same task")
  func callingAddURLOnAlreadyActiveURLReturnsSameTask() async throws {
    let downloadManager = DownloadManager(session: session)

    let url = URL.valid()
    _ = await session.waitRespond(to: url)
    let task1 = await downloadManager.addURL(url)
    await task1.downloadBegan()

    let task2 = await downloadManager.addURL(url)
    #expect(task1 === task2)
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
