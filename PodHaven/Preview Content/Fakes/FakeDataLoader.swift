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
  private let fakeResponses = ThreadSafe<[URL: Data]>([:])

  // MARK: - DataLoading

  private final class FakeCancellable: Cancellable {
    func cancel() {}
    init() {}
  }

  func loadData(
    with request: URLRequest,
    didReceiveData: @escaping (Data, URLResponse) -> Void,
    completion: @escaping (Error?) -> Void
  ) -> Cancellable {
    let url = request.url!

    if let fakeData = fakeResponses()[url] {
      let response = HTTPURLResponse(
        url: url,
        statusCode: 200,
        httpVersion: nil,
        headerFields: nil
      )!
      didReceiveData(fakeData, response)
      completion(nil)
    } else {
      completion(URLError(.fileDoesNotExist))
    }

    return FakeCancellable()
  }

  // MARK: - Test Helpers

  func respond(to url: URL, data: Data) {
    fakeResponses { dict in dict[url] = data }
  }
}
#endif
