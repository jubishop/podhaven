#if DEBUG
// Copyright Justin Bishop, 2025

import Foundation
import Semaphore
import FactoryKit
import IdentifiedCollections

actor FakeDataFetchable: DataFetchable {
  typealias DataHandler = @Sendable (URL) async throws -> (Data, URLResponse)

  @DynamicInjected(\.cacheBackgroundDelegate) private var cacheBackgroundDelegate

  private var defaultHandler: DataHandler
  private var fakeHandlers: [URL: DataHandler] = [:]
  private(set) var requests: [URL] = []
  private(set) var cancelledRequests: [URL] = []
  private(set) var activeRequests = 0
  private(set) var maxActiveRequests = 0

  let downloadTasks = ThreadSafe<
    IdentifiedArray<URLSessionDownloadTask.ID, FakeURLSessionDownloadTask>
  >(IdentifiedArray(id: \.taskID))
  private func addDownloadTask(_ downloadTask: FakeURLSessionDownloadTask) {
    downloadTasks { $0.append(downloadTask) }
  }

  init(
    defaultHandler: @escaping @Sendable DataHandler = { url in
      (url.dataRepresentation, URL.response(url))
    }
  ) {
    self.defaultHandler = defaultHandler
  }

  // MARK: - DataFetchable

  func data(for urlRequest: URLRequest) async throws -> (Data, URLResponse) {
    guard let url = urlRequest.url
    else { Assert.fatal("No URL in URLRequest: \(urlRequest)??") }

    activeRequests += 1
    defer { activeRequests -= 1 }
    maxActiveRequests = max(maxActiveRequests, activeRequests)
    requests.append(url)

    do {
      if let handler = fakeHandlers[url] {
        return try await handler(url)
      }
      return try await defaultHandler(url)
    } catch is CancellationError {
      cancelledRequests.append(url)
      throw CancellationError()
    }
  }

  func data(from url: URL) async throws -> (Data, URLResponse) {
    try await data(for: URLRequest(url: url))
  }

  var allCreatedTasks: IdentifiedArray<URLSessionDownloadTask.ID, any DownloadingTask> {
    get async {
      IdentifiedArray(
        uniqueElements: downloadTasks().map { $0 as any DownloadingTask },
        id: \.taskID
      )
    }
  }

  nonisolated func createDownloadTask(with request: URLRequest, taskDescription: String)
    -> any DownloadingTask
  {
    let downloadTask = FakeURLSessionDownloadTask(
      taskDescription: taskDescription,
      originalRequest: request
    )
    downloadTasks { $0.append(downloadTask) }
    return downloadTask
  }

  // MARK: - Test Helpers

  func setDefaultHandler(_ handler: @escaping DataHandler) {
    defaultHandler = handler
  }

  func clearCustomHandler(for url: URL) {
    fakeHandlers.removeValue(forKey: url)
  }

  func respond(to url: URL, with handler: @escaping DataHandler) {
    fakeHandlers[url] = handler
  }

  func respond(to url: URL, data: Data) {
    respond(to: url) { url in (data, URL.response(url)) }
  }

  func respond(to url: URL, error: any Error) {
    respond(to: url) { _ in throw error }
  }

  func waitRespond(to url: URL, data: Data? = nil) async -> AsyncSemaphore {
    let asyncSemaphore = AsyncSemaphore(value: 0)
    respond(to: url) { url in
      try await asyncSemaphore.waitUnlessCancelled()
      return (data ?? url.dataRepresentation, URL.response(url))
    }
    return asyncSemaphore
  }

  func waitRespond(to url: URL, error: any Error) async -> AsyncSemaphore {
    let asyncSemaphore = AsyncSemaphore(value: 0)
    respond(to: url) { url in
      try await asyncSemaphore.waitUnlessCancelled()
      throw error
    }
    return asyncSemaphore
  }

  func releaseWaitRespond(to url: URL, data: Data? = nil) async -> (
    started: AsyncSemaphore, finish: AsyncSemaphore
  ) {
    let startedSemaphore = AsyncSemaphore(value: 0)
    let finishSemaphore = AsyncSemaphore(value: 0)
    respond(to: url) { url in
      startedSemaphore.signal()
      try await finishSemaphore.waitUnlessCancelled()
      return (data ?? url.dataRepresentation, URL.response(url))
    }
    return (started: startedSemaphore, finish: finishSemaphore)
  }

  func releaseWaitRespond(to url: URL, error: any Error) async -> (
    started: AsyncSemaphore, finish: AsyncSemaphore
  ) {
    let startedSemaphore = AsyncSemaphore(value: 0)
    let finishSemaphore = AsyncSemaphore(value: 0)
    respond(to: url) { url in
      startedSemaphore.signal()
      try await finishSemaphore.waitUnlessCancelled()
      throw error
    }
    return (started: startedSemaphore, finish: finishSemaphore)
  }

  func finishDownload(taskID: URLSessionDownloadTask.ID, didFinishDownloadingTo location: URL) async
  {
    let task = downloadTasks()[id: taskID]!
    await task.assertResumed()
    // URLSession no longer reports a terminal task as outstanding while the
    // app's asynchronous finalization continues.
    downloadTasks { $0.remove(id: taskID) }
    await cacheBackgroundDelegate.urlSession(
      self,
      downloadTask: task,
      didFinishDownloadingTo: location
    )
  }

  func failDownload(taskID: URLSessionDownloadTask.ID, error: any Error) async {
    let task = downloadTasks()[id: taskID]!
    await task.assertResumed()
    downloadTasks { $0.remove(id: taskID) }
    await cacheBackgroundDelegate.urlSession(
      self,
      task: task,
      didCompleteWithError: error
    )
  }

  func progressDownload(
    taskID: URLSessionDownloadTask.ID,
    totalBytesWritten: Int64,
    totalBytesExpectedToWrite: Int64
  ) async {
    guard totalBytesExpectedToWrite > 0 else { return }
    await downloadTasks[id: taskID]!.assertResumed()
    await cacheBackgroundDelegate.urlSession(
      self,
      downloadTask: downloadTasks[id: taskID]!,
      didWriteData: totalBytesWritten,
      totalBytesWritten: totalBytesWritten,
      totalBytesExpectedToWrite: totalBytesExpectedToWrite
    )
  }
}
#endif
