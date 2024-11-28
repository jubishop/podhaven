import Foundation
import OrderedCollections

enum DownloadError: Error, LocalizedError, Sendable, Equatable {
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

  static func == (lhs: DownloadError, rhs: DownloadError) -> Bool {
    switch (lhs, rhs) {
    case (.invalidResponse, .invalidResponse):
      return true
    case (.invalidStatusCode(let lhsCode), .invalidStatusCode(let rhsCode)):
      return lhsCode == rhsCode
    case (.networkError(let lhsMessage), .networkError(let rhsMessage)):
      return lhsMessage.localizedDescription == rhsMessage.localizedDescription
    case (.cancelled, .cancelled):
      return true
    default:
      return false
    }
  }
}

typealias DownloadResult = Result<Data, DownloadError>

final actor DownloadTask: Hashable, Sendable {
  let url: URL
  private let session: Networking
  private weak var manager: DownloadManager?
  private var continuation: CheckedContinuation<DownloadResult, Never>?
  private var result: DownloadResult?

  init(url: URL, session: Networking, manager: DownloadManager) {
    self.url = url
    self.session = session
    self.manager = manager
  }

  func download() async -> DownloadResult {
    guard result == nil else { return result! }
    return await withCheckedContinuation { continuation in
      self.continuation = continuation
    }
  }

  func cancel() async {
    if let manager = manager {
      await manager.cancelDownload(url: url)
    } else {
      _cancel()
    }
  }

  // MARK: - Private Methods

  private func setResult(_ result: DownloadResult) {
    guard self.result == nil else { return }
    self.result = result
    resumeContinuation()
  }

  private func resumeContinuation() {
    if let continuation = continuation, let result = result {
      self.continuation = nil
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
  fileprivate func _cancel() {
    setResult(.failure(.cancelled))
  }

  fileprivate func _start() async {
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
}

final actor DownloadManager: Sendable {
  static let shared = DownloadManager()

  private var activeDownloads: [URL: DownloadTask] = [:]
  private var pendingDownloads: OrderedDictionary<URL, DownloadTask> = [:]
  private let session: Networking
  private let maxConcurrentDownloads: Int

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
    let download = DownloadTask(url: url, session: session, manager: self)
    pendingDownloads[url] = download
    startNextDownload()
    return download
  }

  func cancelDownload(url: URL) async {
    if let activeDownload = activeDownloads.removeValue(forKey: url) {
      await activeDownload._cancel()
      startNextDownload()
    }
    if let pendingDownload = pendingDownloads.removeValue(forKey: url) {
      await pendingDownload._cancel()
    }
  }

  func cancelAllDownloads() async {
    for (_, download) in activeDownloads {
      await download._cancel()
    }
    activeDownloads.removeAll()
    for (_, download) in pendingDownloads {
      await download._cancel()
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
