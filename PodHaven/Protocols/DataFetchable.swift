// Copyright Justin Bishop, 2025

import Foundation

protocol DataFetchable: Sendable {
  // Data APIs
  func data(from url: URL) async throws -> (Data, URLResponse)
  func data(for: URLRequest) async throws -> (Data, URLResponse)
  func validatedData(from url: URL) async throws(DownloadError) -> Data
  func validatedData(for request: URLRequest) async throws(DownloadError) -> Data

  // Background Download APIs
  func scheduleDownload(_ request: URLRequest) async -> Int
  func listDownloadTaskIDs() async -> [Int]
  func cancelDownload(taskID: Int) async
}
