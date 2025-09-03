#if DEBUG
// Copyright Justin Bishop, 2025

import Foundation
import Semaphore
import FactoryKit

actor FakeDataFetchable: DataFetchable {
  typealias DataHandler = @Sendable (URL) async throws -> (Data, URLResponse)

  private var fakeHandlers: [URL: DataHandler] = [:]
  private(set) var requests: [URL] = []
  private(set) var activeRequests = 0
  private(set) var maxActiveRequests = 0
  private var downloadTaskIDs: Set<Int> = []
  private var defaultHandler: DataHandler

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

  func scheduleDownload(_ request: URLRequest) async -> Int {
    let id = Int.random(in: 1_000_000...9_999_999)
    downloadTaskIDs.insert(id)
    return id
  }

  func listDownloadTaskIDs() async -> [Int] {
    Array(downloadTaskIDs)
  }

  func cancelDownload(taskID: Int) async {
    downloadTaskIDs.remove(taskID)
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

  func finishDownload(taskID: Int, tmpURL: URL) async {
    let delegate = Container.shared.cacheBackgroundDelegate()
    await delegate.handleDidFinish(taskIdentifier: taskID, location: tmpURL)
  }

  func failDownload(taskID: Int, error: Error) async {
    let delegate = Container.shared.cacheBackgroundDelegate()
    await delegate.handleDidComplete(taskIdentifier: taskID, error: error)
  }

  func progressDownload(taskID: Int, totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64)
    async
  {
    guard totalBytesExpectedToWrite > 0 else { return }
    let progress = Double(totalBytesWritten) / Double(totalBytesExpectedToWrite)
    let taskMap = Container.shared.taskMapStore()
    if let mg = await taskMap.key(for: taskID) {
      let cs: CacheState = await Container.shared.cacheState()
      await cs.updateProgress(for: mg, progress: progress)
    }
  }
}
#endif
