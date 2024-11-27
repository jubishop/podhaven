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

actor DownloadHandle: Hashable {
  let url: URL
  private let session: URLSession
  private var task: URLSessionDataTask?
  private var continuations: [CheckedContinuation<DownloadResult, Never>] = []

  init(url: URL, session: URLSession) {
    self.url = url
    self.session = session
  }

  /// Starts the download task.
  func start() {
    // Prevent multiple starts
    guard task == nil else { return }

    task = session.dataTask(with: url) { [weak self] data, response, error in
      Task {
        await self?
          .handleCompletion(data: data, response: response, error: error)
      }
    }

    task?.resume()
  }

  /// Awaits the download result, returning a DownloadResult.
  func download() async -> DownloadResult {
    await withCheckedContinuation { continuation in
      continuations.append(continuation)
    }
  }

  /// Cancels the download.
  func cancel() async {
    task?.cancel()
    resumeAllContinuations(with: .failure(.cancelled))
  }

  /// Handles the completion of the download task.
  private func handleCompletion(
    data: Data?,
    response: URLResponse?,
    error: Error?
  ) async {
    defer {
      continuations = []
      task = nil
    }

    let result: DownloadResult
    if let error = error as? URLError, error.code == .cancelled {
      result = .failure(.cancelled)
    } else if let error = error {
      result = .failure(.networkError(error))
    } else if let httpResponse = response as? HTTPURLResponse,
      (200...299).contains(httpResponse.statusCode),
      let data = data
    {
      result = .success(data)
    } else if let httpResponse = response as? HTTPURLResponse {
      result = .failure(.invalidStatusCode(httpResponse.statusCode))
    } else {
      result = .failure(.invalidResponse)
    }

    resumeAllContinuations(with: result)
  }

  /// Resumes all stored continuations with the given result.
  private func resumeAllContinuations(
    with result: DownloadResult
  ) {
    for continuation in continuations {
      continuation.resume(returning: result)
    }
    continuations = []
  }

  // MARK: - Hashable Conformance

  static func == (lhs: DownloadHandle, rhs: DownloadHandle) -> Bool {
    lhs.url == rhs.url
  }

  nonisolated func hash(into hasher: inout Hasher) {
    hasher.combine(url)
  }
}

actor DownloadManager {
  static let shared = DownloadManager()

  private var activeDownloads: [URL: DownloadHandle] = [:]
  private var pendingDownloads: OrderedDictionary<URL, DownloadHandle> = [:]
  private let maxConcurrentDownloads: Int
  let session: URLSession  // Made `let` to allow external modification for testing

  init(session: URLSession = .shared, maxConcurrentDownloads: Int = 8) {
    self.session = session
    self.maxConcurrentDownloads = maxConcurrentDownloads
  }

  /// Adds a URL to the download queue and returns a DownloadHandle.
  /// If the URL is already being downloaded or pending, returns the existing handle.
  func addURL(_ url: URL) async -> DownloadHandle {
    // Check if the URL is already active
    if let activeHandle = activeDownloads[url] {
      return activeHandle
    }

    // Check if the URL is already pending
    if let pendingHandle = pendingDownloads[url] {
      return pendingHandle
    }

    // Create a new DownloadHandle
    let handle = DownloadHandle(url: url, session: session)

    // Add to active or pending based on current active downloads
    if activeDownloads.count < maxConcurrentDownloads {
      activeDownloads[url] = handle
      await startDownload(handle)
    } else {
      pendingDownloads[url] = handle
    }

    return handle
  }

  /// Cancels a specific download by URL.
  func cancelDownload(url: URL) async {
    // Check active downloads
    if let activeHandle = activeDownloads[url] {
      await activeHandle.cancel()
      activeDownloads.removeValue(forKey: url)
      await startNextDownload()
    }

    // Check pending downloads
    if let pendingHandle = pendingDownloads.removeValue(forKey: url) {
      await pendingHandle.cancel()
    }
  }

  /// Cancels all ongoing and pending downloads.
  func cancelAllDownloads() async {
    // Cancel active downloads
    for (_, handle) in activeDownloads {
      await handle.cancel()
    }
    activeDownloads.removeAll()

    // Cancel pending downloads
    for (_, handle) in pendingDownloads {
      await handle.cancel()
    }
    pendingDownloads.removeAll()
  }

  // MARK: - Private Methods

  /// Starts the download for a given handle.
  private func startDownload(_ handle: DownloadHandle) async {
    await handle.start()

    // Start a Task to await the download
    Task { [weak self] in
      guard let self = self else { return }
      let _ = await handle.download()
      await self.removeActiveDownload(url: handle.url)
    }
  }

  /// Removes an active download and starts the next pending download if available.
  private func removeActiveDownload(url: URL) async {
    activeDownloads.removeValue(forKey: url)
    await startNextDownload()
  }

  /// Starts the next download from the pending queue if concurrency limits allow.
  private func startNextDownload() async {
    guard activeDownloads.count < maxConcurrentDownloads,
      !pendingDownloads.isEmpty
    else { return }
    let nextEntry = pendingDownloads.removeFirst()
    activeDownloads[nextEntry.key] = nextEntry.value
    await startDownload(nextEntry.value)
  }
}
