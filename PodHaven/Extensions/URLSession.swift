// Copyright Justin Bishop, 2025

import Foundation
import IdentifiedCollections

extension URLSession: DataFetchable {
  func dataTaskEvents(for request: URLRequest) -> AsyncThrowingStream<DataTaskEvent, any Error> {
    let (events, continuation) = AsyncThrowingStream.makeStream(of: DataTaskEvent.self)
    let task = dataTask(with: request)
    task.delegate = DataTaskEventDelegate(continuation: continuation)
    continuation.onTermination = { _ in task.cancel() }
    task.resume()
    return events
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

private final class DataTaskEventDelegate: NSObject, URLSessionDataDelegate, Sendable {
  private let continuation: AsyncThrowingStream<DataTaskEvent, any Error>.Continuation

  init(continuation: AsyncThrowingStream<DataTaskEvent, any Error>.Continuation) {
    self.continuation = continuation
  }

  func urlSession(
    _ session: URLSession,
    dataTask: URLSessionDataTask,
    didReceive response: URLResponse,
    completionHandler: @escaping @Sendable (URLSession.ResponseDisposition) -> Void
  ) {
    continuation.yield(.response(response))
    completionHandler(.allow)
  }

  func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
    continuation.yield(.data(data))
  }

  func urlSession(
    _ session: URLSession,
    task: URLSessionTask,
    didCompleteWithError error: (any Error)?
  ) {
    if let error {
      continuation.finish(throwing: error)
    } else {
      continuation.finish()
    }
  }
}
