// Copyright Justin Bishop, 2025

import Foundation
import OrderedCollections

typealias DownloadResult = Result<DownloadData, DownloadError>

struct DownloadData: Equatable, Hashable {
  let url: URL
  let data: Data
}

actor DownloadTask {
  let url: URL
  var finished: Bool { result != nil }

  private let session: DataFetchable
  private var beganContinuations: [CheckedContinuation<Void, Never>] = []
  private var finishedContinuations: [CheckedContinuation<DownloadResult, Never>] = []
  private var begun: Bool = false
  private var result: DownloadResult?

  func downloadBegan() async {
    guard !begun else { return }

    await withCheckedContinuation { continuation in
      beganContinuations.append(continuation)
    }
  }

  func downloadFinished() async throws(DownloadError) -> DownloadData {
    if let result { return try result.get() }

    let result = await withCheckedContinuation { continuation in
      finishedContinuations.append(continuation)
    }
    return try result.get()
  }

  func cancel() {
    haveFinished(.failure(DownloadError.cancelled(url)))
  }

  // MARK: - Fileprivate Methods

  fileprivate init(url: URL, session: DataFetchable) {
    self.url = url
    self.session = session
  }

  fileprivate func download() async {
    if self.result != nil { return }
    do {
      haveBegun()
      let data = try await session.validatedData(from: url)
      haveFinished(.success(DownloadData(url: url, data: data)))
    } catch {
      haveFinished(.failure(error))
    }
    guard self.result != nil
    else { Assert.fatal("No result by the end of download()?!") }
  }

  // MARK: - Private Helpers

  private func haveBegun() {
    guard !begun
    else { return }

    begun = true
    for beganContinuation in beganContinuations {
      beganContinuation.resume()
    }
    beganContinuations.removeAll()
  }

  private func haveFinished(_ result: DownloadResult) {
    guard self.result == nil
    else { return }

    self.result = result
    haveBegun()
    for finishedContinuation in finishedContinuations {
      finishedContinuation.resume(returning: result)
    }
    finishedContinuations.removeAll()
  }
}

actor DownloadManager {
  private var activeDownloads: [URL: DownloadTask] = [:]
  private var pendingDownloads: OrderedDictionary<URL, DownloadTask> = [:]
  private let session: DataFetchable
  private let maxConcurrentDownloads: Int

  var remainingDownloads: Int { pendingDownloads.count + activeDownloads.count }

  init(session: DataFetchable, maxConcurrentDownloads: Int = 32) {
    self.session = session
    self.maxConcurrentDownloads = maxConcurrentDownloads
  }

  func addURL(_ url: URL) -> DownloadTask {
    if let activeDownload = activeDownloads[url] {
      return activeDownload
    }
    if let pendingDownload = pendingDownloads[url] {
      // Move existing pending download to top of queue
      pendingDownloads.updateValue(pendingDownload, forKey: url, insertingAt: 0)
      return pendingDownload
    }
    let download = DownloadTask(url: url, session: session)
    pendingDownloads[url] = download
    startNextDownload()
    return download
  }

  func cancelDownload(url: URL) async {
    if let activeDownload = activeDownloads.removeValue(forKey: url) {
      await activeDownload.cancel()
      startNextDownload()
    }
    if let pendingDownload = pendingDownloads.removeValue(forKey: url) {
      await pendingDownload.cancel()
    }
  }

  func cancelAllDownloads() async {
    for (_, downloadTask) in activeDownloads {
      await downloadTask.cancel()
    }
    activeDownloads.removeAll()
    for (_, downloadTask) in pendingDownloads {
      await downloadTask.cancel()
    }
    pendingDownloads.removeAll()
  }

  // MARK: - Private Helpers

  private func startNextDownload() {
    guard
      activeDownloads.count < maxConcurrentDownloads,
      !pendingDownloads.isEmpty
    else { return }
    let nextEntry = pendingDownloads.removeFirst()
    activeDownloads[nextEntry.key] = nextEntry.value
    executeDownload(nextEntry.value)
  }

  private func executeDownload(_ downloadTask: DownloadTask) {
    Task {  // Intentionally not weak so the Manager isn't deallocated before tasks complete
      await downloadTask.download()
      activeDownloads.removeValue(forKey: downloadTask.url)
      Task { startNextDownload() }
    }
  }
}
