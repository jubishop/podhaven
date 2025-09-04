#if DEBUG
// Copyright Justin Bishop, 2025

import Foundation
import Semaphore
import FactoryKit
import IdentifiedCollections

actor FakeDataFetchable: DataFetchable {
  typealias DataHandler = @Sendable (URL) async throws -> (Data, URLResponse)

  private var defaultHandler: DataHandler
  private var fakeHandlers: [URL: DataHandler] = [:]
  private(set) var requests: [URL] = []
  private(set) var activeRequests = 0
  private(set) var maxActiveRequests = 0

  private var downloadTasks: IdentifiedArray<DownloadTaskID, FakeURLSessionDownloadTask> =
    IdentifiedArray(id: \.taskID)
  private func addDownloadTask(_ downloadTask: FakeURLSessionDownloadTask) {
    downloadTasks.append(downloadTask)
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

    if let handler = fakeHandlers[url] {
      return try await handler(url)
    }

    return try await defaultHandler(url)
  }

  func data(from url: URL) async throws -> (Data, URLResponse) {
    try await data(for: URLRequest(url: url))
  }

  func validatedData(from url: URL) async throws(PodHaven.DownloadError) -> Data {
    try await DownloadError.catch {
      let (data, _) = try await data(from: url)
      return data
    }
  }

  func validatedData(for request: URLRequest) async throws(PodHaven.DownloadError) -> Data {
    try await DownloadError.catch {
      let (data, _) = try await data(for: request)
      return data
    }
  }

  var allCreatedTasks: IdentifiedArray<DownloadTaskID, any DownloadingTask> {
    get async {
      IdentifiedArray(
        uniqueElements: downloadTasks.map { $0 as any DownloadingTask },
        id: \.taskID
      )
    }
  }

  nonisolated func createDownloadTask(with request: URLRequest) -> any DownloadingTask {
    let downloadTask = FakeURLSessionDownloadTask()
    Task { await addDownloadTask(downloadTask) }
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
    respond(to: url) { url in
      (data, URL.response(url))
    }
  }

  func respond(to url: URL, error: Error) {
    respond(to: url) { _ in
      throw error
    }
  }

  func waitThenRespond(to url: URL, data: Data? = nil) async -> AsyncSemaphore {
    let asyncSemaphore = AsyncSemaphore(value: 0)
    respond(to: url) { url in
      try await asyncSemaphore.waitUnlessCancelled()
      return (data ?? url.dataRepresentation, URL.response(url))
    }
    return asyncSemaphore
  }

  func waitThenRespond(to url: URL, error: Error) async -> AsyncSemaphore {
    let asyncSemaphore = AsyncSemaphore(value: 0)
    respond(to: url) { url in
      try await asyncSemaphore.waitUnlessCancelled()
      throw error
    }
    return asyncSemaphore
  }

  func finishDownload(taskID: DownloadTaskID, tmpURL: URL) async {
    await downloadTasks[id: taskID]?.assertResumed()
    await downloadTasks[id: taskID]?.assertCancelled(false)
    let delegate = Container.shared.cacheBackgroundDelegate()
    await delegate.handleDidFinish(taskID: taskID, location: tmpURL)
  }

  func failDownload(taskID: DownloadTaskID, error: Error) async {
    await downloadTasks[id: taskID]?.assertResumed()
    await downloadTasks[id: taskID]?.assertCancelled(false)
    let delegate = Container.shared.cacheBackgroundDelegate()
    await delegate.handleDidComplete(taskID: taskID, error: error)
  }

  func progressDownload(
    taskID: DownloadTaskID,
    totalBytesWritten: Int64,
    totalBytesExpectedToWrite: Int64
  )
    async
  {
    guard totalBytesExpectedToWrite > 0 else { return }
    await downloadTasks[id: taskID]?.assertResumed()
    await downloadTasks[id: taskID]?.assertCancelled(false)

    let progress = Double(totalBytesWritten) / Double(totalBytesExpectedToWrite)
    let episode = try! await Container.shared.repo().episode(taskID)!
    let cs: CacheState = await Container.shared.cacheState()
    await cs.updateProgress(for: episode.id, progress: progress)
  }
}
#endif
