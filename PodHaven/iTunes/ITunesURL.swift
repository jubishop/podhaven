// Copyright Justin Bishop, 2025

import Foundation
import Tagged

typealias ITunesEpisodeID = Tagged<ITunesURL, Int>
typealias ITunesPodcastID = Tagged<ITunesURL, Int>

struct ITunesURL {
  private static let podcastEntity = "podcast"
  private static let episodeEntity = "podcastEpisode"

  // MARK: - URL Analysis

  static func isPodcastURL(_ url: URL) -> Bool {
    // https://podcasts.apple.com/us/podcast/podcast-name/id1234567890
    url.scheme == "https" && url.host?.contains("podcasts.apple.com") == true
  }

  static func isEpisodeURL(_ url: URL) -> Bool {
    isPodcastURL(url) && url.query?.contains("i=") == true
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
      ]
    )
  }

  static func topPodcastsRequest(genreID: Int?, limit: Int) -> URLRequest {
    var pathComponents = ["", AppInfo.countryCode, "rss", "toppodcasts", "limit=\(limit)"]

    if let genreID {
      pathComponents.append("genre=\(genreID)")
    }

    pathComponents.append("json")

    return buildRequest(path: pathComponents.joined(separator: "/"))
  }

  // MARK: - Static Lookups

  static func lookupEpisodeRequest(
    episodeIDs: [ITunesEpisodeID],
    limit: Int? = nil
  ) -> URLRequest {
    lookupRequest(iTunesIDs: episodeIDs.map(String.init), entity: episodeEntity, limit: limit)
  }

  static func lookupPodcastRequest(
    podcastIDs: [ITunesPodcastID],
    limit: Int? = nil
  ) -> URLRequest {
    lookupRequest(iTunesIDs: podcastIDs.map(String.init), entity: podcastEntity, limit: limit)
  }

  private static func lookupRequest(
    iTunesIDs: [String],
    entity: String,
    limit: Int? = nil
  ) -> URLRequest {
    var queryItems: [URLQueryItem] = [
      URLQueryItem(name: "id", value: iTunesIDs.joined(separator: ",")),
      URLQueryItem(name: "entity", value: entity),
      URLQueryItem(name: "country", value: AppInfo.countryCode),
    ]

    if let limit {
      queryItems.append(URLQueryItem(name: "limit", value: String(limit)))
    }

    return buildRequest(path: "/lookup", queryItems: queryItems)
  }

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
