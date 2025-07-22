// Copyright Justin Bishop, 2025

import Foundation

enum ShareHelpers {
  static func shareURL(with url: URL) -> URL {
    URL(string: "podhaven://share?url=\(url.absoluteString)")!
  }

  static func itunesPodcastLookupURL(for itunesID: String) -> URL {
    URL(string: "https://itunes.apple.com/lookup?id=\(itunesID)&entity=podcast")!
  }

  static func itunesEpisodeLookupURL(for podcastID: String) -> URL {
    URL(string: "https://itunes.apple.com/lookup?id=\(podcastID)&entity=podcastEpisode&limit=200")!
  }

  static func itunesPodcastURL(for itunesID: String, withTitle title: String) -> URL {
    URL(string: "https://podcasts.apple.com/us/podcast/\(title)/id\(itunesID)")!
  }

  static func itunesEpisodeURL(for podcastID: String, episodeID: String, withTitle title: String)
    -> URL
  {
    URL(string: "https://podcasts.apple.com/us/podcast/\(title)/id\(podcastID)?i=\(episodeID)")!
  }
}
