// Copyright Justin Bishop, 2026

import Foundation

struct HTTPValidators: Hashable, Sendable {
  let eTag: String?
  let lastModified: String?

  init?(eTag: String?, lastModified: String?) {
    guard eTag != nil || lastModified != nil else { return nil }
    self.eTag = eTag
    self.lastModified = lastModified
  }

  init?(_ response: URLResponse) {
    guard let httpResponse = response as? HTTPURLResponse else { return nil }
    self.init(
      eTag: httpResponse.value(forHTTPHeaderField: "ETag"),
      lastModified: httpResponse.value(forHTTPHeaderField: "Last-Modified")
    )
  }

  func conditionalRequest(for url: URL) -> URLRequest {
    // A locally cached copy would turn the server's 304 back into a 200.
    var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData)
    if let eTag {
      request.setValue(eTag, forHTTPHeaderField: "If-None-Match")
    }
    if let lastModified {
      request.setValue(lastModified, forHTTPHeaderField: "If-Modified-Since")
    }
    return request
  }
}
