// Copyright Justin Bishop, 2025

import Foundation

protocol DownloadingTask: Sendable {
  var taskID: URLSessionDownloadTask.ID { get }
  func resume()
  func cancel()
}
