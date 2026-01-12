// Copyright Justin Bishop, 2025

import Foundation

enum ShareHelpers {
  static func shareURL(with url: URL) -> URL {
    var components = URLComponents(string: "podhaven://share")!
    components.queryItems = [URLQueryItem(name: "url", value: url.absoluteString)]
    return components.url!
  }

  static func itunesPodcastURL(for itunesID: String, withTitle title: String) -> URL {
    URL(string: "https://podcasts.apple.com/us/podcast/\(title)/id\(itunesID)")!
  }

  static func itunesEpisodeURL(for podcastID: String, episodeID: String, withTitle title: String)
    -> URL
  {
    URL(string: "https://podcasts.apple.com/us/podcast/\(title)/id\(podcastID)?i=\(episodeID)")!
  }

  static func podcastURL(feedURL: String) -> URL {
    var components = URLComponents(string: "https://www.artisanalsoftware.com/podhaven/podcast")!
    components.queryItems = [URLQueryItem(name: "feedURL", value: feedURL)]
    return components.url!
  }

  static func episodeURL(feedURL: String, guid: String) -> URL {
    var components = URLComponents(string: "https://www.artisanalsoftware.com/podhaven/episode")!
    components.queryItems = [
      URLQueryItem(name: "feedURL", value: feedURL),
      URLQueryItem(name: "guid", value: guid),
    ]
    return components.url!
  }
}
