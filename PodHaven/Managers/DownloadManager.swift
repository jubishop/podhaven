import Foundation
import OrderedCollections

enum DownloadError: Error, LocalizedError {
  case invalidResponse
  case invalidStatusCode(Int)
  case networkError(Error)
  case cancelled

  var errorDescription: String? {
    switch self {
    case .invalidResponse:
      return "Received an invalid response from the server."
    case .invalidStatusCode(let statusCode):
      return "Received HTTP status code \(statusCode)."
    case .networkError(let error):
      return "A network error occurred: \(error.localizedDescription)"
    case .cancelled:
      return "The download was cancelled."
    }
  }
}

typealias DownloadResult = Result<Data, DownloadError>

actor DownloadTask: Hashable {
  let url: URL
  private let session: URLSession
  private var continuation: CheckedContinuation<DownloadResult, Never>?
  private var result: DownloadResult?

  init(url: URL, session: URLSession) {
    self.url = url
    self.session = session
  }

  /// Starts the download task.
  func start() async {
    guard result == nil else { return }
    do {
      let (data, response) = try await session.data(from: url)
      guard let httpResponse = response as? HTTPURLResponse else {
        throw DownloadError.invalidResponse
      }
      guard (200...299).contains(httpResponse.statusCode) else {
        throw DownloadError.invalidStatusCode(httpResponse.statusCode)
      }
      setResult(.success(data))
    } catch {
      let finalError: DownloadError
      if let downloadError = error as? DownloadError {
        finalError = downloadError
      } else if error is CancellationError {
        finalError = .cancelled
      } else {
        finalError = .networkError(error)
      }
      setResult(.failure(finalError))
    }
  }

  /// Awaits the download result, returning a DownloadResult.
  func download() async -> DownloadResult {
    guard let result = result else {
      return await withCheckedContinuation { continuation in
        self.continuation = continuation
      }
    }
    return result
  }

  // MARK: - Private Methods

  private func setResult(_ result: DownloadResult) {
    guard self.result == nil else { return }
    self.result = result
    resumeContinuation()
  }

  private func resumeContinuation() {
    if let continuation = continuation, let result = result {
      continuation.resume(returning: result)
    }
  }

  // MARK: - Hashable Conformance

  static func == (lhs: DownloadTask, rhs: DownloadTask) -> Bool {
    lhs.url == rhs.url
  }

  nonisolated func hash(into hasher: inout Hasher) {
    hasher.combine(url)
  }
}

extension DownloadTask {
  fileprivate func cancel() {
    setResult(.failure(.cancelled))
  }
}

actor DownloadManager {
  static let shared = DownloadManager()

  private var activeDownloads: [URL: DownloadTask] = [:]
  private var pendingDownloads: OrderedDictionary<URL, DownloadTask> = [:]
  private let session: URLSession
  private let maxConcurrentDownloads: Int

  init(session: URLSession = .shared, maxConcurrentDownloads: Int = 8) {
    self.session = session
    self.maxConcurrentDownloads = maxConcurrentDownloads
  }

  /// Adds a URL to the download queue and returns a DownloadTask.
  /// If the URL is already being downloaded or pending, returns the existing download.
  func addURL(_ url: URL) async -> DownloadTask {
    // Check if the URL is already active
    if let activeDownload = activeDownloads[url] {
      return activeDownload
    }

    // Check if the URL is already pending
    if let pendingDownload = pendingDownloads[url] {
      return pendingDownload
    }

    // Create a new DownloadTask
    let download = DownloadTask(url: url, session: session)

    // Add to pending and potentially start it.
    pendingDownloads[url] = download
    await startNextDownload()

    return download
  }

  /// Cancels a specific download by URL.
  func cancelDownload(url: URL) async {
    // Check active downloads
    if let activeDownload = activeDownloads.removeValue(forKey: url) {
      await activeDownload.cancel()
      await startNextDownload()
    }

    // Check pending downloads
    if let pendingDownload = pendingDownloads.removeValue(forKey: url) {
      await pendingDownload.cancel()
    }
  }

  /// Cancels all ongoing and pending downloads.
  func cancelAllDownloads() async {
    // Cancel active downloads
    for (_, download) in activeDownloads {
      await download.cancel()
    }
    activeDownloads.removeAll()

    // Cancel pending downloads
    for (_, download) in pendingDownloads {
      await download.cancel()
    }
    pendingDownloads.removeAll()
  }

  // MARK: - Private Methods

  /// Starts the download for a given download.
  private func startDownload(_ download: DownloadTask) async {
    await download.start()
    await self.removeActiveDownload(url: download.url)
  }

  /// Removes an active download and starts the next pending download if available.
  private func removeActiveDownload(url: URL) async {
    activeDownloads.removeValue(forKey: url)
    await startNextDownload()
  }

  /// Starts the next download from the pending queue if concurrency limits allow.
  private func startNextDownload() async {
    guard
      activeDownloads.count < maxConcurrentDownloads,
      !pendingDownloads.isEmpty
    else { return }
    let nextEntry = pendingDownloads.removeFirst()
    activeDownloads[nextEntry.key] = nextEntry.value
    await startDownload(nextEntry.value)
  }
}
