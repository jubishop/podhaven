// Copyright Justin Bishop, 2025

import Foundation

@testable import PodHaven

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
    ShareURL.podcast(feedURL: FeedURL(URL(string: feedURL)!))!
  }

  static func episodeURL(feedURL: String, guid: String) -> URL {
    ShareURL.episode(feedURL: FeedURL(URL(string: feedURL)!), guid: GUID(guid))!
  }
}
