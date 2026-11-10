// Copyright Justin Bishop, 2025

import Foundation
import IdentifiedCollections

enum DataTaskEvent: Sendable {
  case response(URLResponse)
  case data(Data)
}

protocol DataFetchable: Sendable {
  // Data APIs
  func data(from url: URL) async throws -> (Data, URLResponse)
  func data(for: URLRequest) async throws -> (Data, URLResponse)
  func dataTaskEvents(for request: URLRequest) -> AsyncThrowingStream<DataTaskEvent, any Error>
  func validatedData(for request: URLRequest) async throws -> Data
  func validatedData(from url: URL, byteLimit: Int) async throws -> Data

  // Background Download APIs
  var allCreatedTasks: IdentifiedArray<URLSessionDownloadTask.ID, any DownloadingTask> { get async }
  func createDownloadTask(with request: URLRequest, taskDescription: String) -> any DownloadingTask
}

extension DataFetchable {
  func validatedData(for request: URLRequest) async throws -> Data {
    let (data, response) = try await data(for: request)
    try Self.validateStatus(of: response, requestURL: Self.url(of: request))
    return data
  }

  func validatedData(from url: URL, byteLimit: Int) async throws -> Data {
    try await validatedResponse(for: URLRequest(url: url), byteLimit: byteLimit).data
  }

  func validatedResponse(for request: URLRequest, byteLimit: Int) async throws -> (
    data: Data, response: URLResponse
  ) {
    let requestURL = Self.url(of: request)
    var response: URLResponse?
    var data = Data()
    for try await event in dataTaskEvents(for: request) {
      switch event {
      case .response(let received):
        try Self.validateStatus(of: received, requestURL: requestURL)
        guard received.expectedContentLength <= byteLimit else {
          throw ResponseTooLargeError(
            byteLimit: byteLimit,
            responseURL: received.url ?? requestURL
          )
        }
        response = received
      case .data(let chunk):
        guard chunk.count <= byteLimit - data.count else {
          throw ResponseTooLargeError(
            byteLimit: byteLimit,
            responseURL: response?.url ?? requestURL
          )
        }
        data.append(chunk)
      }
    }
    // Cancelling the consumer ends the stream without an error.
    try Task.checkCancellation()
    guard let response else { throw URLError(.badServerResponse) }
    return (data, response)
  }

  private static func url(of request: URLRequest) -> URL {
    guard let url = request.url
    else { Assert.fatal("No URL in URLRequest: \(request)") }
    return url
  }

  private static func validateStatus(of response: URLResponse, requestURL: URL) throws {
    guard let httpResponse = response as? HTTPURLResponse,
      !(200...299).contains(httpResponse.statusCode)
    else { return }

    throw HTTPStatusError(
      statusCode: httpResponse.statusCode,
      responseURL: httpResponse.url ?? requestURL
    )
  }
}
