// Copyright Justin Bishop, 2025

import Foundation
import IdentifiedCollections
import Tagged

typealias SessionConfigurationID = Tagged<any DataFetchable, String>

protocol DataFetchable: Sendable {
  // Data APIs
  func data(from url: URL) async throws -> (Data, URLResponse)
  func data(for: URLRequest) async throws -> (Data, URLResponse)
  func validatedData(from url: URL) async throws(DownloadError) -> Data
  func validatedData(for request: URLRequest) async throws(DownloadError) -> Data

  // Background Download APIs
  var allCreatedTasks: IdentifiedArray<URLSessionDownloadTask.ID, any DownloadingTask> { get async }
  func createDownloadTask(with request: URLRequest) -> any DownloadingTask
}
