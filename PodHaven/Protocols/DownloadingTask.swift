// Copyright Justin Bishop, 2025

import Foundation
import Tagged

typealias DownloadTaskID = Tagged<any DownloadingTask, Int>

protocol DownloadingTask: Sendable {
  var taskID: DownloadTaskID { get }
  func resume()
  func cancel()
}
