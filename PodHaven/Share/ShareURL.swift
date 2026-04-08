// Copyright Justin Bishop, 2026

import Foundation
import Tagged

enum ShareURL {
  private static let host = "www.artisanalsoftware.com"
  private static let scheme = "https"

  static func podcast(feedURL: FeedURL) -> URL? {
    var components = URLComponents()
    components.scheme = scheme
    components.host = host
    components.path = "/podhaven/podcast"
    components.queryItems = [
      URLQueryItem(name: "feedURL", value: feedURL.rawValue.absoluteString)
    ]
    return components.url
  }

  static func episode(feedURL: FeedURL, guid: GUID, startTime: Int? = nil) -> URL? {
    var components = URLComponents()
    components.scheme = scheme
    components.host = host
    components.path = "/podhaven/episode"
    components.queryItems = [
      URLQueryItem(name: "feedURL", value: feedURL.rawValue.absoluteString),
      URLQueryItem(name: "guid", value: guid.rawValue),
    ]
    if let startTime {
      components.queryItems?
        .append(
          URLQueryItem(name: "startTime", value: String(startTime))
        )
    }
    return components.url
  }
}
