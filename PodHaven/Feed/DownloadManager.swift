import Foundation
import OrderedCollections

typealias DownloadResult = Result<DownloadData, DownloadError>

struct DownloadData: Sendable, Equatable, Hashable {
  let url: URL
  let data: Data
}

final actor DownloadTask: Sendable {
  let url: URL
  var finished: Bool { result != nil }

  private let session: Networking
  private var beganContinuations: [CheckedContinuation<Void, Never>] = []
  private var finishedContinuations:
    [CheckedContinuation<DownloadResult, Never>] = []
  private var begun: Bool = false
  private var result: DownloadResult?

  fileprivate init(url: URL, session: Networking) {
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
    if let result = result { return result }

    return await withCheckedContinuation { continuation in
      finishedContinuations.append(continuation)
    }
  }

  func cancel() {
    haveFinished(.failure(.cancelled))
  }

  // MARK: - Private Methods

  private func haveBegun() {
    guard !begun else { return }
    begun = true
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
  fileprivate func download() async -> DownloadResult {
    if let result = self.result { return result }
    do {
      haveBegun()
      let (data, response) = try await session.data(from: url)
      guard let httpResponse = response as? HTTPURLResponse else {
        throw DownloadError.invalidResponse
      }
      guard (200...299).contains(httpResponse.statusCode) else {
        throw DownloadError.invalidStatusCode(httpResponse.statusCode)
      }
      haveFinished(.success(DownloadData(url: url, data: data)))
    } catch {
      let finalError: DownloadError
      if let downloadError = error as? DownloadError {
        finalError = downloadError
      } else if error is CancellationError {
        finalError = .cancelled
      } else {
        finalError = .networkError(String(describing: error))
      }
      haveFinished(.failure(finalError))
    }
    guard let result = self.result else {
      fatalError("No result by the end of download()?!")
    }
    return result
  }
}

final actor DownloadManager: Sendable {
  private var activeDownloads: [URL: DownloadTask] = [:]
  private var pendingDownloads: OrderedDictionary<URL, DownloadTask> = [:]
  private let session: Networking
  private let maxConcurrentDownloads: Int
  private let asyncStream: AsyncStream<DownloadResult>
  private let streamContinuation: AsyncStream<DownloadResult>.Continuation

  var remainingDownloads: Int {
    pendingDownloads.count + activeDownloads.count
  }

  init(
    session: Networking = URLSession.shared,
    maxConcurrentDownloads: Int = 8
  ) {
    self.session = session
    self.maxConcurrentDownloads = maxConcurrentDownloads
    (self.asyncStream, self.streamContinuation) = AsyncStream.makeStream(
      of: DownloadResult.self
    )
  }

  deinit {
    streamContinuation.finish()
  }

  func downloads() -> AsyncStream<DownloadResult> { asyncStream }

  @discardableResult
  func addURL(_ url: URL) -> DownloadTask {
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

  @discardableResult
  func addURLs(_ urls: [URL]) -> [DownloadTask] {
    var downloadTasks = [DownloadTask](capacity: urls.count)
    for url in urls {
      downloadTasks.append(addURL(url))
    }
    return downloadTasks
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

  private func executeDownload(_ downloadTask: DownloadTask) {
    Task {
      let downloadResult = await downloadTask.download()
      streamContinuation.yield(downloadResult)
      activeDownloads.removeValue(forKey: downloadTask.url)
      startNextDownload()
    }
  }
}
