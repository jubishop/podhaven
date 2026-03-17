// Copyright Justin Bishop, 2026

import Foundation
import UIKit
import WidgetKit

struct PodcastDetailEntry: TimelineEntry {
  let date: Date
  let podcastTitle: String
  let lastUpdatedFormatted: String
  let podcastArtwork: UIImage?
  let podcastURL: URL?
  let episodes: [WidgetEpisodeList.Episode]
  let isPlaceholder: Bool

  private static let podcastDetailBaseURL = WidgetInfo.podcastDetailBaseURL

  static let empty = PodcastDetailEntry(
    date: Date(),
    podcastTitle: "",
    lastUpdatedFormatted: "",
    podcastArtwork: nil,
    podcastURL: nil,
    episodes: [],
    isPlaceholder: true
  )

  static let preview = PodcastDetailEntry(
    date: Date(),
    podcastTitle: "Swift by Sundell",
    lastUpdatedFormatted: "3/14/26",
    podcastArtwork: nil,
    podcastURL: {
      var components = URLComponents(string: "podhaven://widget/podcast-detail")!
      components.queryItems = [
        URLQueryItem(name: "feedURL", value: "https://swiftbysundell.com/podcast/feed.rss")
      ]
      return components.url
    }(),
    episodes: [
      WidgetEpisodeList.Episode(
        id: 1,
        title: "Understanding Swift Concurrency",
        pubDateFormatted: "3/14/26",
        durationFormatted: "41:00",
        artwork: nil,
        deepLinkURL: podcastDetailBaseURL.appending(path: "episode/1")
      ),
      WidgetEpisodeList.Episode(
        id: 2,
        title: "The Future of SwiftUI",
        pubDateFormatted: "3/10/26",
        durationFormatted: "58:30",
        artwork: nil,
        deepLinkURL: podcastDetailBaseURL.appending(path: "episode/2")
      ),
      WidgetEpisodeList.Episode(
        id: 3,
        title: "Building Better Apps with Swift Testing",
        pubDateFormatted: "3/05/26",
        durationFormatted: "22:15",
        artwork: nil,
        deepLinkURL: podcastDetailBaseURL.appending(path: "episode/3")
      ),
      WidgetEpisodeList.Episode(
        id: 4,
        title: "Deep Dive into GRDB",
        pubDateFormatted: "2/28/26",
        durationFormatted: "35:45",
        artwork: nil,
        deepLinkURL: podcastDetailBaseURL.appending(path: "episode/4")
      ),
    ],
    isPlaceholder: false
  )
}
