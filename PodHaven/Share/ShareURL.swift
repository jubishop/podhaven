// Copyright Justin Bishop, 2026

import Foundation
import Tagged

enum ShareURL {
  private static let host = "www.artisanalsoftware.com"
  private static let scheme = "https"

  static func universalLinkDestination(_ url: URL) -> (
    feedURL: FeedURL, guid: GUID?, startTime: Int?
  )? {
    guard url.scheme?.lowercased() == scheme,
      let incomingHost = url.host?.lowercased(),
      ["artisanalsoftware.com", host].contains(incomingHost),
      url.user == nil, url.password == nil,
      url.port == nil || url.port == 443,
      [
        "/podhaven/podcast", "/podhaven/episode",
        "/podhaven/open/podcast", "/podhaven/open/episode",
      ]
      .contains(url.path),
      let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems
    else { return nil }

    let feedItems = items.filter { $0.name == "feedURL" }
    guard feedItems.count == 1,
      let feedValue = feedItems.first?.value, feedValue.count <= 2048,
      let feedURL = URL(string: feedValue),
      let feedScheme = feedURL.scheme?.lowercased(),
      ["http", "https"].contains(feedScheme),
      let feedHost = feedURL.host, !feedHost.isEmpty
    else { return nil }

    var guid: GUID?
    if url.path.hasSuffix("/episode") {
      let guidItems = items.filter { $0.name == "guid" }
      guard guidItems.count == 1,
        let value = guidItems.first?.value, !value.isEmpty, value.count <= 512
      else { return nil }
      guid = GUID(value)
    }

    var startTime: Int?
    let timeItems = items.filter { $0.name == "startTime" }
    if timeItems.count == 1, let value = timeItems.first?.value,
      !value.isEmpty, value.allSatisfy({ $0.isASCII && $0.isNumber }),
      let seconds = Int(value), seconds > 0
    {
      startTime = seconds
    }
    return (FeedURL(feedURL), guid, startTime)
  }

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
