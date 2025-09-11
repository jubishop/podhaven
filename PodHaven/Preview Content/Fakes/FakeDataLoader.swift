#if DEBUG
// Copyright Justin Bishop, 2025

import FactoryKit
import Foundation
import Nuke

extension Container {
  var dataLoader: Factory<FakeDataLoader> {
    Factory(self) { FakeDataLoader() }.scope(.cached)
  }
}

struct FakeDataLoader: DataLoading {
  typealias DataHandler = @Sendable (URL) async throws -> Data

  private let fakeHandlers = ThreadSafe<[URL: DataHandler]>([:])

  // MARK: - DataLoading

  private final class TaskCancellable<Success: Sendable, Failure: Error>: Cancellable {
    private let task: Task<Success, Failure>

    init(task: Task<Success, Failure>) {
      self.task = task
    }

    func cancel() {
      task.cancel()
    }
  }

  func loadData(
    with request: URLRequest,
    didReceiveData: @escaping (Data, URLResponse) -> Void,
    completion: @escaping (Error?) -> Void
  ) -> Cancellable {
    let url = request.url!
    let callbacks = UnsafeSendable((didReceiveData: didReceiveData, completion: completion))

    let task = Task {
      if let fakeHandler = fakeHandlers[url] {
        let fakeData = try await fakeHandler(url)
        try Task.checkCancellation()
        callbacks.didReceiveData(
          fakeData,
          HTTPURLResponse(
            url: url,
            statusCode: 200,
            httpVersion: nil,
            headerFields: nil
          )!
        )
        callbacks.completion(nil)
      } else {
        callbacks.completion(URLError(.fileDoesNotExist))
      }
    }

    return TaskCancellable(task: task)
  }

  // MARK: - Test Helpers

  func respond(to url: URL, with handler: @escaping DataHandler) {
    fakeHandlers[url] = handler
  }

  func respond(to url: URL, data: Data) {
    respond(to: url) { url in data }
  }

  func respond(to url: URL, error: Error) {
    respond(to: url) { _ in throw error }
  }
}
#endif
