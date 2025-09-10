// Copyright Justin Bishop, 2025

import Foundation
import Nuke

final class FakeDataLoader: DataLoading {
  private let mockResponses: [URL: Data]

  init(mockResponses: [URL: Data] = [:]) {
    self.mockResponses = mockResponses
  }

  func loadData(
    with request: URLRequest,
    didReceiveData: @escaping (Data, URLResponse) -> Void,
    completion: @escaping (Error?) -> Void
  ) -> Cancellable {
    let url = request.url!

    //if let mockData = mockResponses[url] {
    let response = HTTPURLResponse(
      url: url,
      statusCode: 200,
      httpVersion: nil,
      headerFields: nil
    )!
    didReceiveData(
      PreviewBundle.loadImageData(named: "this-american-life-episode1", in: .EpisodeThumbnails),
      response
    )
    completion(nil)
    //      } else {
    //        // Return a default placeholder image or error
    //        completion(URLError(.fileDoesNotExist))
    //      }

    return FakeCancellable()
  }
}

private final class FakeCancellable: Cancellable {
  func cancel() {}
  init() {}
}
