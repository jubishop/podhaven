// Copyright Justin Bishop, 2024

import Foundation

extension URL {
  static let placeholder = URL(string: "about:blank")!

  func convertToValidURL() throws -> URL {
    guard var components = URLComponents(url: self, resolvingAgainstBaseURL: false)
    else { throw URLError(.badURL, userInfo: ["message": "URL: \(self) cannot be components."]) }

    if components.scheme == nil {
      guard let modifiedComponents = URLComponents(string: "https://" + self.absoluteString)
      else { throw URLError(.badURL, userInfo: ["message": "URL: \(self) cannot prepend https."]) }
      components = modifiedComponents
    }

    if components.scheme == "http" { components.scheme = "https" }
    guard let url = components.url
    else { throw URLError(.badURL, userInfo: ["message": "No components.url: \(components)"]) }

    try url.validate()
    return url
  }

  func validate() throws {
    guard let scheme = self.scheme, scheme == "https"
    else { throw URLError(.badURL, userInfo: ["message": "URL: \(self) must use https scheme."]) }
    guard let host = self.host, !host.isEmpty
    else { throw URLError(.badURL, userInfo: ["message": "URL: \(self) must have  a valid host."]) }
  }
}
