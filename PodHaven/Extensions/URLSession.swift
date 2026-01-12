// Copyright Justin Bishop, 2025

import Foundation
import IdentifiedCollections

extension URLSession: DataFetchable {
  func validatedData(from url: URL) async throws(DownloadError) -> Data {
    try await validatedData(for: URLRequest(url: url))
  }

  func validatedData(for request: URLRequest) async throws(DownloadError) -> Data {
    guard let url = request.url
    else { throw DownloadError.invalidRequest(request) }

    return try await DownloadError.catch {
      do {
        let (data, response) = try await data(for: request)
        if let httpResponse = response as? HTTPURLResponse {
          guard (200...299).contains(httpResponse.statusCode)
          else { throw DownloadError.notOKResponseCode(code: httpResponse.statusCode, url: url) }
        }
        return data
      } catch is CancellationError {
        throw DownloadError.cancelled(url)
      }
    }
  }

  var allCreatedTasks: IdentifiedArray<URLSessionDownloadTask.ID, any DownloadingTask> {
    get async {
      IdentifiedArray(
        uniqueElements: await allTasks.compactMap { $0 as? URLSessionDownloadTask },
        id: \.taskID
      )
    }
  }

  func createDownloadTask(with request: URLRequest) -> any DownloadingTask {
    downloadTask(with: request)
  }
}
