// Copyright Justin Bishop, 2025

import Foundation

protocol DownloadingTask: Sendable {
  var taskID: URLSessionDownloadTask.ID { get }
  // Stable per-episode identifier set at creation. Used to map a finished
  // download back to its episode without relying on the reusable taskID.
  var taskDescription: String? { get }
  // Used by the delegate to defensively verify the completed download's URL
  // matches the resolved media URL of the episode it was attributed to.
  var originalRequest: URLRequest? { get }
  func resume()
  func cancel()
}
