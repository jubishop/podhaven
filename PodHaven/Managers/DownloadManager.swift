import Foundation
import OrderedCollections

typealias DownloadResult = Result<Data, DownloadError>

final actor DownloadTask: Sendable {
  let url: URL
  private let session: Networking
  private var beganContinuations: [CheckedContinuation<Void, Never>] = []
  private var finishedContinuations:
    [CheckedContinuation<DownloadResult, Never>] = []
  private var begun: Bool = false
  private var result: DownloadResult?

  init(url: URL, session: Networking) {
    self.url = url
    self.session = session
  }

  func downloadBegan() async {
    guard !begun else { return }

    await withCheckedContinuation { continuation in
      beganContinuations.append(continuation)
    }
  }

  func downloadFinished() async -> DownloadResult {
    guard result == nil else { return result! }

    return await withCheckedContinuation { continuation in
      finishedContinuations.append(continuation)
    }
  }

  func cancel() {
    haveFinished(.failure(.cancelled))
  }

  // MARK: - Private Methods

  private func haveBegun() {
    guard !self.begun else { return }
    self.begun = true
    for beganContinuation in beganContinuations {
      beganContinuation.resume()
    }
    beganContinuations.removeAll()
  }

  private func haveFinished(_ result: DownloadResult) {
    guard self.result == nil else { return }
    self.result = result
    haveBegun()
    for finishedContinuation in finishedContinuations {
      finishedContinuation.resume(returning: result)
    }
    finishedContinuations.removeAll()
  }
}

extension DownloadTask {
  fileprivate func _start() async {
    guard result == nil else { return }
    do {
      haveBegun()
      let (data, response) = try await session.data(from: url)
      guard let httpResponse = response as? HTTPURLResponse else {
        throw DownloadError.invalidResponse
      }
      guard (200...299).contains(httpResponse.statusCode) else {
        throw DownloadError.invalidStatusCode(httpResponse.statusCode)
      }
      haveFinished(.success(data))
    } catch {
      let finalError: DownloadError
      if let downloadError = error as? DownloadError {
        finalError = downloadError
      } else if error is CancellationError {
        finalError = .cancelled
      } else {
        finalError = .networkError(error)
      }
      haveFinished(.failure(finalError))
    }
  }
}

final actor DownloadManager: Sendable {
  private var activeDownloads: [URL: DownloadTask] = [:]
  private var pendingDownloads: OrderedDictionary<URL, DownloadTask> = [:]
  private let session: Networking
  private let maxConcurrentDownloads: Int

  var remainingDownloads: Int {
    pendingDownloads.count + activeDownloads.count
  }

  init(
    session: Networking = URLSession.shared,
    maxConcurrentDownloads: Int = 8
  ) {
    self.session = session
    self.maxConcurrentDownloads = maxConcurrentDownloads
  }

  func addURL(_ url: URL) async -> DownloadTask {
    if let activeDownload = activeDownloads[url] {
      return activeDownload
    }
    if let pendingDownload = pendingDownloads[url] {
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
    for (_, download) in activeDownloads {
      await download.cancel()
    }
    activeDownloads.removeAll()
    for (_, download) in pendingDownloads {
      await download.cancel()
    }
    pendingDownloads.removeAll()
  }

  // MARK: - Private Methods

  private func startNextDownload() {
    guard
      activeDownloads.count < maxConcurrentDownloads,
      !pendingDownloads.isEmpty
    else { return }
    let nextEntry = pendingDownloads.removeFirst()
    activeDownloads[nextEntry.key] = nextEntry.value
    executeDownload(nextEntry.value)
  }

  private func executeDownload(_ download: DownloadTask) {
    Task {
      await download._start()
      activeDownloads.removeValue(forKey: download.url)
      startNextDownload()
    }
  }
}
