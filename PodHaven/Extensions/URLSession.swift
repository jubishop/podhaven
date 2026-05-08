// Copyright Justin Bishop, 2025

import Foundation
import IdentifiedCollections

extension URLSession: DataFetchable {
  func validatedData(from url: URL) async throws -> Data {
    try await validatedData(for: URLRequest(url: url))
  }

  func validatedData(for request: URLRequest) async throws -> Data {
    guard request.url != nil
    else { Assert.fatal("No URL in URLRequest: \(request)") }

    let (data, response) = try await data(for: request)
    if let httpResponse = response as? HTTPURLResponse,
      !(200...299).contains(httpResponse.statusCode)
    {
      throw URLError(.badServerResponse)
    }
    return data
  }

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
