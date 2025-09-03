// Copyright Justin Bishop, 2025 

import Foundation

extension URLSessionDownloadTask: DownloadingTask {
  var taskID: DownloadTaskID { DownloadTaskID(taskIdentifier) }
}
