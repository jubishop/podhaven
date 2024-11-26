import Foundation

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
    return DownloadManager(maxConcurrentDownloads: 16)
  }()

  private var pendingURLs: Set<URL> = []
  private var handlers: [URL: DownloadHandler] = [:]
  private var activeDownloads: [URL: Task<Void, Never>] = [:]
  private let maxConcurrentDownloads: Int
  private let session: URLSession

  init(session: URLSession? = nil, maxConcurrentDownloads: Int = 8) {
    if let session = session {
      self.session = session
    } else {
      let configuration = URLSessionConfiguration.default
      configuration.allowsCellularAccess = true
      configuration.waitsForConnectivity = false
      configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
      configuration.httpMaximumConnectionsPerHost = maxConcurrentDownloads
      self.session = URLSession(configuration: configuration)
    }
    self.maxConcurrentDownloads = maxConcurrentDownloads
  }

  func addURL(_ url: URL, handler: @escaping DownloadHandler) {
    handlers[url] = handler

    if !activeDownloads.keys.contains(url) {
      pendingURLs.insert(url)
      Task { await startNextDownloads() }
    }
  }

  private func startNextDownloads() async {
    let availableSlots = maxConcurrentDownloads - activeDownloads.count
    guard availableSlots > 0 else {
      return
    }

    let downloadsToStart = min(availableSlots, pendingURLs.count)
    for _ in 0..<downloadsToStart {
      if let url = pendingURLs.popFirst() {
        activeDownloads[url] = Task { await download(url: url) }
      }
    }
  }

  private func download(url: URL) async {
    defer {
      handlers.removeValue(forKey: url)
      activeDownloads.removeValue(forKey: url)
      Task { await startNextDownloads() }
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

  func cancelDownload(url: URL) async {
    if pendingURLs.contains(url) {
      pendingURLs.remove(url)
      if let handler = handlers[url] {
        Task { @MainActor in handler(.failure(.cancelled)) }
        handlers.removeValue(forKey: url)
      }
      return
    }

    if let task = activeDownloads[url] {
      task.cancel()
      activeDownloads.removeValue(forKey: url)
    }
  }

  func cancelAllDownloads() async {
    for url in pendingURLs {
      if let handler = handlers[url] {
        Task { @MainActor in handler(.failure(.cancelled)) }
      }
    }
    pendingURLs.removeAll()
    handlers.removeAll()

    for (_, task) in activeDownloads {
      task.cancel()
    }
    activeDownloads.removeAll()
  }
}
