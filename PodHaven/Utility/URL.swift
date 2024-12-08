// Copyright Justin Bishop, 2024

import Foundation

extension URL {
  public func convertToValidURL() throws -> URL {
    guard
      var components = URLComponents(
        url: self,
        resolvingAgainstBaseURL: false
      )
    else {
      throw URLError(
        .badURL,
        userInfo: ["message": "URL: \(self) is invalid."]
      )
    }
    if components.scheme == nil || components.scheme == "http" {
      components.scheme = "https"
    }
    components.fragment = nil
    guard let url = components.url else {
      throw URLError(
        .badURL,
        userInfo: ["message": "Components: \(components) are invalid."]
      )
    }
    try url.validate()
    return url
  }

  public func validate() throws {
    guard let scheme = self.scheme, scheme == "https"
    else {
      throw URLError(
        .badURL,
        userInfo: ["message": "URL: \(self) must use https scheme."]
      )
    }
    guard let host = self.host, !host.isEmpty else {
      throw URLError(
        .badURL,
        userInfo: [
          "message": "URL: \(self) must be an absolute URL with a valid host."
        ]
      )
    }
    guard self.fragment == nil else {
      throw URLError(
        .badURL,
        userInfo: ["message": "URL: \(self) should not contain a fragment."]
      )
    }
  }
}
