#if DEBUG
// Copyright Justin Bishop, 2025

import FactoryKit
import Foundation
import Nuke
import SwiftUI
import ConcurrencyExtras

extension Container {
  var fakeDataLoader: Factory<FakeDataLoader> {
    Factory(self) { FakeDataLoader() }.scope(.cached)
  }
}

struct FakeDataLoader: DataLoading {
  typealias DataHandler = @Sendable (URL) async throws -> Data

  let loadedURLs = ThreadSafe<Set<URL>>([])

  private let defaultHandler = ThreadSafe<DataHandler?>(nil)
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
    loadedURLs { set in set.insert(url) }

    let callbacks = UncheckedSendable((didReceiveData: didReceiveData, completion: completion))
    let task = Task {
      if let fakeHandler = fakeHandlers[url] ?? defaultHandler() {
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

  func setDefaultHandler(_ handler: @escaping DataHandler) {
    defaultHandler(handler)
  }

  func clearCustomHandler(for url: URL) {
    fakeHandlers { dict in dict.removeValue(forKey: url) }
  }

  func respond(to url: URL, with handler: @escaping DataHandler) {
    fakeHandlers[url] = handler
  }

  func respond(to url: URL, data: Data) {
    respond(to: url) { url in data }
  }

  func respond(to url: URL, error: Error) {
    respond(to: url) { _ in throw error }
  }

  static func create(_ url: URL) -> UIImage {
    let hash = abs(url.absoluteString.hashValue)
    let size = CGSize(width: 100, height: 100)
    let color = UIColor(
      red: CGFloat((hash >> 16) & 0xFF) / 255.0,
      green: CGFloat((hash >> 8) & 0xFF) / 255.0,
      blue: CGFloat(hash & 0xFF) / 255.0,
      alpha: 1.0
    )

    return UIGraphicsImageRenderer(size: size)
      .image { context in
        color.setFill()
        context.fill(CGRect(origin: .zero, size: size))
      }
  }
}
#endif
