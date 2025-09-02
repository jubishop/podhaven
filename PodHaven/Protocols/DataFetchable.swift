// Copyright Justin Bishop, 2025

import Foundation

protocol DataFetchable: Sendable {
  // Data APIs
  func data(from url: URL) async throws -> (Data, URLResponse)
  func data(for: URLRequest) async throws -> (Data, URLResponse)
  func validatedData(from url: URL) async throws(DownloadError) -> Data
  func validatedData(for request: URLRequest) async throws(DownloadError) -> Data

  // Background download APIs (no-ops for non-downloading use sites)
  func scheduleDownload(_ request: URLRequest) async -> Int
  func listDownloadTaskIDs() async -> [Int]
  func cancelDownload(taskID: Int) async
}

extension URLSession: DataFetchable {
  func scheduleDownload(_ request: URLRequest) async -> Int {
    let task = downloadTask(with: request)
    task.resume()
    return task.taskIdentifier
  }

  func listDownloadTaskIDs() async -> [Int] {
    let tasks: [URLSessionTask] = await withCheckedContinuation { cont in
      getAllTasks { cont.resume(returning: $0) }
    }
    return tasks.map { $0.taskIdentifier }
  }

  func cancelDownload(taskID: Int) async {
    let tasks: [URLSessionTask] = await withCheckedContinuation { cont in
      getAllTasks { cont.resume(returning: $0) }
    }
    tasks.first(where: { $0.taskIdentifier == taskID })?.cancel()
  }
}
