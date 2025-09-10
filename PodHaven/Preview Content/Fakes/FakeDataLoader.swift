#if DEBUG
// Copyright Justin Bishop, 2025

import FactoryKit
import Foundation
import Nuke

extension Container {
  var dataLoader: Factory<DataLoading> {
    Factory(self) { FakeDataLoader() }.scope(.cached)
  }
}

struct FakeDataLoader: DataLoading {
  private let mockResponses = ThreadSafe<[URL: Data]>([:])

  func setResponse(for url: URL, to data: Data) {
    mockResponses { dict in dict[url] = data }
  }

  func loadData(
    with request: URLRequest,
    didReceiveData: @escaping (Data, URLResponse) -> Void,
    completion: @escaping (Error?) -> Void
  ) -> Cancellable {
    let url = request.url!

    if let mockData = mockResponses()[url] {
      let response = HTTPURLResponse(
        url: url,
        statusCode: 200,
        httpVersion: nil,
        headerFields: nil
      )!
      didReceiveData(
        mockData,
        response
      )
      completion(nil)
    } else {
      // Return a default placeholder image or error
      completion(URLError(.fileDoesNotExist))
    }

    return FakeCancellable()
  }
}

private final class FakeCancellable: Cancellable {
  func cancel() {}
  init() {}
}
#endif
