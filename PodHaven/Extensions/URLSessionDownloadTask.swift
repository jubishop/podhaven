// Copyright Justin Bishop, 2025

import Foundation
import Tagged

extension URLSessionDownloadTask: DownloadingTask {
  typealias ID = Tagged<any DownloadingTask, Int>
  var taskID: ID { ID(taskIdentifier) }
}
