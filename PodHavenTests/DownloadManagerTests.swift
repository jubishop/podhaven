// Copyright Justin Bishop, 2025

import Foundation
import Semaphore
import Testing

@testable import PodHaven

@Suite("of DownloadManager tests")
actor DownloadManagerTests {
  private let session: DataFetchableMock

  init() {
    session = DataFetchableMock()
  }

  @Test("that a single download works successfully")
  func singleSuccessfulDownload() async {
    let downloadManager = DownloadManager(session: session)

    let url = URL.valid()
    let downloadTask = await downloadManager.addURL(url)
    let result = await downloadTask.downloadFinished()
    #expect(result.isSuccessfulWith(DownloadData(url: url)))
    #expect(await downloadTask.finished)
  }

  @Test("that an array of downloads work successfully")
  func arrayOfSuccessfulDownloads() async {
    let downloadManager = DownloadManager(session: session)

    let urls = (1...100).map { URL(string: "https://example.com/data\($0)")! }
    let downloadTasks = await downloadManager.addURLs(urls)
    var results = [DownloadResult](capacity: urls.count)
    for downloadTask in downloadTasks {
      results.append(await downloadTask.downloadFinished())
    }
    #expect(results.count == urls.count)
  }

  @Test("that maxConcurrentDownloads is respected and downloadBegan() works")
  func maxConcurrentDownloads() async {
    let maxConcurrentDownloads = 20
    let downloadManager = DownloadManager(
      session: session,
      maxConcurrentDownloads: maxConcurrentDownloads
    )

    let urls = (1...100).map { URL(string: "https://example.com/data\($0)")! }
    var tasks: [DownloadTask] = []
    for url in urls {
      await session.set(url, .delay(.milliseconds(20)))
      let task = await downloadManager.addURL(url)
      tasks.append(task)
    }
    let counter = Counter()
    await withDiscardingTaskGroup { group in
      for task in tasks {
        group.addTask {
          await task.downloadBegan()
          await counter.increment()
          _ = await task.downloadFinished()
          await counter.decrement()
        }
      }
    }
    let maxTally = await counter.maxValue
    #expect(abs(maxTally - maxConcurrentDownloads) <= 2)
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
    var result = await task.downloadFinished()
    #expect(result.isCancelled)

    // Even after the url data has returned, the result remains cancelled.
    try await Task.sleep(for: .milliseconds(100))
    result = await task.downloadFinished()
    #expect(result.isCancelled)
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
    var result = await task.downloadFinished()
    #expect(result.isCancelled)
    var result2 = await task2.downloadFinished()
    #expect(result2.isCancelled)

    // Even after the url data has returned, the results remains cancelled.
    try await Task.sleep(for: .milliseconds(100))
    result = await task.downloadFinished()
    #expect(result.isCancelled)
    result2 = await task2.downloadFinished()
    #expect(result2.isCancelled)
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
      _ = await task.downloadFinished()
    }
    let requests = await session.requests
    #expect(requests == urls)
  }

  @Test("that you can call downloadFinished() multiple times before completion")
  func multipleDownloadsCalls() async throws {
    let downloadManager = DownloadManager(session: session)

    let url = URL.valid()
    await session.set(url, .delay(.milliseconds(100)))
    let task = await downloadManager.addURL(url)
    let downloadCount = Counter()
    let taskCount = 5
    for _ in 0..<taskCount {
      Task {
        let result = await task.downloadFinished()
        #expect(result.isSuccessfulWith(DownloadData(url: url)))
        await downloadCount.increment()
      }
    }
    try await Task.sleep(for: .milliseconds(200))
    let tally = await downloadCount.value
    #expect(tally == taskCount)
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
    let result = await task.downloadFinished()
    #expect(result.isSuccessfulWith(DownloadData(url: url2)))
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
