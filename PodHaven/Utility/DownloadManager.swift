// Copyright Justin Bishop, 2025

import Foundation
import IdentifiedCollections
import Logging

typealias DownloadResult = Result<DownloadData, any Error>

struct DownloadData: Equatable, Hashable {
  let url: URL
  let data: Data
  let validators: HTTPValidators?
}

actor DownloadTask: Identifiable {
  typealias RawValue = URL

  nonisolated var id: URL { url }

  let url: URL
  var finished: Bool { finishedLatch.isOpen }

  private let request: URLRequest
  private let session: any DataFetchable
  private let byteLimit: Int
  private let beganLatch = AsyncLatch<Void>()
  private let finishedLatch = AsyncLatch<DownloadResult>()
  private var fetchTask: Task<DownloadData, any Error>?
  private weak var owner: DownloadManager?

  func downloadBegan() async throws {
    try await beganLatch.wait()
  }

  func downloadFinished() async throws -> DownloadData {
    let result = try await finishedLatch.wait()
    return try result.get()
  }

  func cancel() async {
    guard !finishedLatch.isOpen else { return }
    // Capture-then-clear so concurrent cancel()s after this point are no-ops
    // and the owner is notified at most once per task.
    let owner = self.owner
    self.owner = nil
    finalizeCancelled()
    await owner?.handleDirectCancel(self)
  }

  // MARK: - Fileprivate Methods

  fileprivate nonisolated var cancelled: Bool {
    guard case .failure(let error)? = finishedLatch.openValue else { return false }
    return error is CancellationError
  }

  fileprivate init(
    url: URL,
    validators: HTTPValidators?,
    session: any DataFetchable,
    byteLimit: Int,
    owner: DownloadManager
  ) {
    self.url = url
    if let validators {
      request = validators.conditionalRequest(for: url)
    } else {
      request = URLRequest(url: url)
    }
    self.session = session
    self.byteLimit = byteLimit
    self.owner = owner
  }

  // Cancellation initiated by the owning manager. The manager has already
  // removed the task from its state, so we skip the owner callback.
  fileprivate func cancelFromOwner() {
    guard !finishedLatch.isOpen else { return }
    owner = nil
    finalizeCancelled()
  }

  fileprivate func download() async {
    guard !finishedLatch.isOpen else { return }

    beganLatch.open()

    let fetchTask = Task { [session, request, byteLimit, url] () async throws -> DownloadData in
      let (data, response) = try await session.validatedResponse(
        for: request,
        byteLimit: byteLimit
      )
      return DownloadData(url: url, data: data, validators: HTTPValidators(response))
    }
    self.fetchTask = fetchTask
    defer { self.fetchTask = nil }

    do {
      finishedLatch.open(.success(try await fetchTask.value))
    } catch {
      finishedLatch.open(.failure(error))
    }
  }

  // MARK: - Private Helpers

  private func finalizeCancelled() {
    fetchTask?.cancel()
    beganLatch.open()
    finishedLatch.open(.failure(CancellationError()))
  }
}

actor DownloadManager {
  private static let log = Log.as("DownloadManager")

  private var activeDownloads: [URL: DownloadTask] = [:]
  private var pendingDownloads: IdentifiedArray<URL, DownloadTask> = []
  private let session: any DataFetchable
  private let byteLimit: Int
  private let maxConcurrentDownloads: Int

  var remainingDownloads: Int { pendingDownloads.count + activeDownloads.count }

  init(session: any DataFetchable, byteLimit: Int, maxConcurrentDownloads: Int = 32) {
    self.session = session
    self.byteLimit = byteLimit
    self.maxConcurrentDownloads = maxConcurrentDownloads
  }

  func hasURL(_ url: URL) -> Bool {
    activeDownloads[url] != nil || pendingDownloads[id: url] != nil
  }

  func addURL(_ url: URL, validators: HTTPValidators? = nil) -> DownloadTask {
    defer {
      Self.log.trace(
        """
        addURL: \(url.hash())
          activeDownloads: \(activeDownloads.keys.map { $0.hash() })
          pendingDownloads: \(pendingDownloads.ids.map { $0.hash() })
        """
      )
    }

    if let activeDownload = activeDownloads[url] {
      guard activeDownload.cancelled else { return activeDownload }
      activeDownloads.removeValue(forKey: url)
    }

    if let pendingDownload = pendingDownloads[id: url] {
      guard pendingDownload.cancelled else { return pendingDownload }
      pendingDownloads.remove(id: url)
    }

    let download = DownloadTask(
      url: url,
      validators: validators,
      session: session,
      byteLimit: byteLimit,
      owner: self
    )
    pendingDownloads.append(download)

    startNextDownload()
    return download
  }

  func cancelDownload(url: URL) async {
    if let activeDownload = activeDownloads.removeValue(forKey: url) {
      await activeDownload.cancelFromOwner()
      startNextDownload()
    }
    if let pendingDownload = pendingDownloads.remove(id: url) {
      await pendingDownload.cancelFromOwner()
    }
  }

  func cancelAllDownloads() async {
    let activeDownloadTasks = Array(activeDownloads.values)
    let pendingDownloadTasks = Array(pendingDownloads)
    activeDownloads.removeAll()
    pendingDownloads.removeAll()

    for downloadTask in activeDownloadTasks {
      await downloadTask.cancelFromOwner()
    }
    for downloadTask in pendingDownloadTasks {
      await downloadTask.cancelFromOwner()
    }
  }

  // MARK: - Fileprivate Helpers

  // Called by DownloadTask when the task was cancelled directly (not via
  // cancelDownload/cancelAllDownloads). Keep manager state in sync and free
  // the concurrency slot the cancelled task was holding.
  fileprivate func handleDirectCancel(_ downloadTask: DownloadTask) {
    let url = downloadTask.url
    if activeDownloads[url] === downloadTask {
      activeDownloads.removeValue(forKey: url)
      startNextDownload()
    } else if pendingDownloads[id: url] === downloadTask {
      pendingDownloads.remove(id: url)
    }
  }

  // MARK: - Private Helpers

  private func startNextDownload() {
    guard
      activeDownloads.count < maxConcurrentDownloads,
      !pendingDownloads.isEmpty
    else { return }
    let nextDownloadTask = pendingDownloads.removeFirst()
    activeDownloads[nextDownloadTask.id] = nextDownloadTask
    executeDownload(nextDownloadTask)
  }

  private func executeDownload(_ downloadTask: DownloadTask) {
    Task {  // Intentionally not weak so the Manager isn't deallocated before tasks complete
      await downloadTask.download()
      if activeDownloads[downloadTask.url] === downloadTask {
        activeDownloads.removeValue(forKey: downloadTask.url)
      }
      Task { startNextDownload() }
    }
  }
}
