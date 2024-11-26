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

typealias DownloadHandler = (Result<Data, DownloadError>) -> Void

actor DownloadManager {
  static let feed: DownloadManager = {
    let maxConcurrentDownloads = 16
    let configuration = URLSessionConfiguration.default
    configuration.allowsCellularAccess = true
    configuration.waitsForConnectivity = false
    configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
    configuration.httpMaximumConnectionsPerHost = maxConcurrentDownloads
    return DownloadManager(
      session: URLSession(configuration: configuration),
      maxConcurrentDownloads: maxConcurrentDownloads
    )
  }()

  private var handlers: [URL: DownloadHandler] = [:]
  private var pendingDownloads: OrderedSet<URL> = []
  private var activeDownloads: [URL: Task<Void, Never>] = [:]
  private let maxConcurrentDownloads: Int
  private let session: URLSession

  init(session: URLSession = .shared, maxConcurrentDownloads: Int = 8) {
    self.session = session
    self.maxConcurrentDownloads = maxConcurrentDownloads
  }

  func addURL(_ url: URL, handler: @escaping DownloadHandler) {
    handlers[url] = handler
    addPendingDownload(url)
  }

  func cancelDownload(url: URL) async {
    if pendingDownloads.contains(url) {
      pendingDownloads.remove(url)
      if let handler = handlers[url] {
        Task { @MainActor in handler(.failure(.cancelled)) }
        handlers.removeValue(forKey: url)
      }
    }
    if let task = activeDownloads[url] {
      task.cancel()
      removeActiveDownload(url)
    }
  }

  func cancelAllDownloads() async {
    for url in pendingDownloads {
      if let handler = handlers[url] {
        Task { @MainActor in handler(.failure(.cancelled)) }
      }
    }
    for (_, task) in activeDownloads {
      task.cancel()
    }
    handlers.removeAll()
    pendingDownloads.removeAll()
    activeDownloads.removeAll()
  }

  // MARK: - Private
  private func addPendingDownload(_ url: URL) {
    if !activeDownloads.keys.contains(url) && !pendingDownloads.contains(url) {
      pendingDownloads.append(url)
      startNextDownloads()
    }
  }

  private func removeActiveDownload(_ url: URL) {
    handlers.removeValue(forKey: url)
    activeDownloads.removeValue(forKey: url)
    startNextDownloads()
  }

  private func startNextDownloads() {
    let availableSlots = maxConcurrentDownloads - activeDownloads.count
    for _ in 0..<availableSlots {
      guard !pendingDownloads.isEmpty else { break }
      let url = pendingDownloads.removeFirst()
      activeDownloads[url] = Task { await download(url: url) }
    }
  }

  private func download(url: URL) async {
    defer {
      removeActiveDownload(url)
    }
    let handler = handlers[url]
    do {
      let (data, response) = try await session.data(from: url)
      guard let httpResponse = response as? HTTPURLResponse else {
        throw DownloadError.invalidResponse
      }
      guard (200...299).contains(httpResponse.statusCode) else {
        throw DownloadError.invalidStatusCode(httpResponse.statusCode)
      }
      if let handler = handler {
        Task { @MainActor in handler(.success(data)) }
      }
    } catch {
      let finalError: DownloadError
      if let downloadError = error as? DownloadError {
        finalError = downloadError
      } else if error is CancellationError {
        finalError = .cancelled
      } else {
        finalError = .networkError(error)
      }
      if let handler = handler {
        Task { @MainActor in handler(.failure(finalError)) }
      }
    }
  }

}
