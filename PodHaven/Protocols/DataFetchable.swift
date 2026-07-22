// Copyright Justin Bishop, 2025

import Foundation
import IdentifiedCollections

protocol DataFetchable: Sendable {
  // Data APIs
  func data(from url: URL) async throws -> (Data, URLResponse)
  func data(for: URLRequest) async throws -> (Data, URLResponse)
  func validatedData(from url: URL) async throws -> Data
  func validatedData(for request: URLRequest) async throws -> Data

  // Background Download APIs
  var allCreatedTasks: IdentifiedArray<URLSessionDownloadTask.ID, any DownloadingTask> { get async }
  func createDownloadTask(with request: URLRequest, taskDescription: String) -> any DownloadingTask
}

extension DataFetchable {
  func validatedData(from url: URL) async throws -> Data {
    try await validatedData(for: URLRequest(url: url))
  }

  func validatedData(for request: URLRequest) async throws -> Data {
    guard let requestURL = request.url
    else { Assert.fatal("No URL in URLRequest: \(request)") }

    let (data, response) = try await data(for: request)
    guard let httpResponse = response as? HTTPURLResponse,
      !(200...299).contains(httpResponse.statusCode)
    else { return data }

    throw HTTPStatusError(
      statusCode: httpResponse.statusCode,
      responseURL: httpResponse.url ?? requestURL
    )
  }
}
