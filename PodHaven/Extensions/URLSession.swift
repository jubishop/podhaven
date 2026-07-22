// Copyright Justin Bishop, 2025

import Foundation
import IdentifiedCollections

extension URLSession: DataFetchable {
  var allCreatedTasks: IdentifiedArray<URLSessionDownloadTask.ID, any DownloadingTask> {
    get async {
      IdentifiedArray(
        uniqueElements: await allTasks.compactMap { $0 as? URLSessionDownloadTask },
        id: \.taskID
      )
    }
  }

  func createDownloadTask(with request: URLRequest, taskDescription: String)
    -> any DownloadingTask
  {
    let task = downloadTask(with: request)
    task.taskDescription = taskDescription
    return task
  }
}
