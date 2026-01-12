// Copyright Justin Bishop, 2025

import Foundation
import Tagged

extension URLSessionDownloadTask: DownloadingTask {
  typealias ID = Tagged<URLSessionDownloadTask, Int>
  var taskID: ID { ID(taskIdentifier) }
}
