// Copyright Justin Bishop, 2025

import Foundation
import Tagged

typealias ITunesPodcastID = Tagged<ITunesURL, Int>

struct ITunesURL {
  private static let podcastEntity = "podcast"

  // MARK: - URL Analysis

  static func isPodcastURL(_ url: URL) -> Bool {
    // https://podcasts.apple.com/us/podcast/podcast-name/id1234567890
    url.scheme == "https" && url.host?.contains("podcasts.apple.com") == true
  }

  static func extractPodcastID(from url: URL) throws(ShareError) -> ITunesPodcastID {
    let pathComponents = url.path.components(separatedBy: "/")
    for component in pathComponents {
      if component.hasPrefix("id"), component.count > 2 {
        let idString = String(component.dropFirst(2))
        if let iTunesID = Int(idString) { return ITunesPodcastID(rawValue: iTunesID) }
      }
    }

    throw ShareError.noIdentifierFound(url)
  }

  // MARK: - Static Searches

  static func searchRequest(for term: String, limit: Int) -> URLRequest {
    buildRequest(
      path: "/search",
      queryItems: [
        URLQueryItem(name: "term", value: term),
        URLQueryItem(name: "media", value: podcastEntity),
        URLQueryItem(name: "entity", value: podcastEntity),
        URLQueryItem(name: "limit", value: String(limit)),
        URLQueryItem(name: "country", value: AppInfo.countryCode),
      ]
    )
  }

  static func topPodcastsRequest(genreID: Int? = nil, limit: Int) -> URLRequest {
    var pathComponents = [AppInfo.countryCode, "rss", "toppodcasts", "limit=\(limit)"]

    if let genreID {
      pathComponents.append("genre=\(genreID)")
    }

    pathComponents.append("json")

    return buildRequest(path: "/" + pathComponents.joined(separator: "/"))
  }

  // MARK: - Static Lookups

  static func lookupRequest(podcastIDs: [ITunesPodcastID]) -> URLRequest {
    buildRequest(
      path: "/lookup",
      queryItems: [
        URLQueryItem(name: "id", value: podcastIDs.map(String.init).joined(separator: ",")),
        URLQueryItem(name: "media", value: podcastEntity),
        URLQueryItem(name: "entity", value: podcastEntity),
        URLQueryItem(name: "country", value: AppInfo.countryCode),
      ]
    )
  }

  // MARK: - Private Helpers

  private static func buildRequest(path: String, queryItems: [URLQueryItem] = []) -> URLRequest {
    var components = URLComponents()
    components.scheme = "https"
    components.host = "itunes.apple.com"
    components.path = path
    components.queryItems = queryItems

    guard let url = components.url
    else { Assert.fatal("Unable to build request from components: \(components)") }

    var request = URLRequest(url: url)
    request.httpMethod = "GET"
    request.addValue("PodHaven", forHTTPHeaderField: "User-Agent")
    return request
  }
}
