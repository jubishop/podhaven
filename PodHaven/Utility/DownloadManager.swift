// Copyright Justin Bishop, 2025

import Foundation
import IdentifiedCollections
import Logging

typealias DownloadResult = Result<DownloadData, any Error>

struct DownloadData: Equatable, Hashable {
  let url: URL
  let data: Data
}

actor DownloadTask: Identifiable {
  typealias RawValue = URL

  nonisolated var id: URL { url }

  let url: URL
  var finished: Bool { finishedLatch.isOpen }

  private let session: any DataFetchable
  private let beganLatch = AsyncLatch<Void>()
  private let finishedLatch = AsyncLatch<DownloadResult>()
  private var fetchTask: Task<Data, any Error>?
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
    await owner?.handleDirectCancel(url: url)
  }

  // MARK: - Fileprivate Methods

  fileprivate init(url: URL, session: any DataFetchable, owner: DownloadManager) {
    self.url = url
    self.session = session
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

    let fetchTask = Task { [session, url] () async throws -> Data in
      try await session.validatedData(from: url)
    }
    self.fetchTask = fetchTask
    defer { self.fetchTask = nil }

    do {
      let data = try await fetchTask.value
      finishedLatch.open(.success(DownloadData(url: url, data: data)))
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
  private let maxConcurrentDownloads: Int

  var remainingDownloads: Int { pendingDownloads.count + activeDownloads.count }

  init(session: any DataFetchable, maxConcurrentDownloads: Int = 32) {
    self.session = session
    self.maxConcurrentDownloads = maxConcurrentDownloads
  }

  func hasURL(_ url: URL) -> Bool {
    activeDownloads[url] != nil || pendingDownloads[id: url] != nil
  }

  func addURL(_ url: URL) -> DownloadTask {
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
      return activeDownload
    }

    if let pendingDownload = pendingDownloads[id: url] {
      return pendingDownload
    }

    let download = DownloadTask(url: url, session: session, owner: self)
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
  fileprivate func handleDirectCancel(url: URL) {
    if activeDownloads.removeValue(forKey: url) != nil {
      startNextDownload()
    } else {
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
      activeDownloads.removeValue(forKey: downloadTask.url)
      Task { startNextDownload() }
    }
  }
}
