// Copyright Justin Bishop, 2026

import FactoryKit
import Foundation

@testable import PodHaven

// A series stored without its feed's newest episode, so refreshing it from `data`
// inserts exactly one episode newer than every stored one.
enum NewEpisodeFeed {
  static var data: Data {
    PreviewBundle.loadAsset(named: "hardfork_short_updated", in: .FeedRSS)
  }

  static func insertSeries(
    feedURL: URL = URL(string: "https://example.com/feed.rss")!,
    lastUpdate: Date? = nil,
    subscriptionDate: Date? = Date(),
    queueAllEpisodes: QueueAllEpisodes = .never,
    cacheAllEpisodes: CacheAllEpisodes = .never,
    alwaysTranscribeNewEpisodes: Bool = false,
    notifyNewEpisodes: Bool = false
  ) async throws -> PodcastSeries {
    let podcastFeed = try await PodcastFeed.parse(data, from: FeedURL(feedURL))
    let basePodcast = try podcastFeed.toUnsavedPodcast()
    let storedEpisodes = podcastFeed.toUnsavedEpisodes()
      .sorted { $0.pubDate > $1.pubDate }
      .dropFirst()
    return try await Container.shared.repo()
      .insertSeries(
        UnsavedPodcastSeries(
          unsavedPodcast: try Create.unsavedPodcast(
            feedURL: basePodcast.feedURL,
            title: basePodcast.title,
            image: basePodcast.image,
            description: basePodcast.description,
            link: basePodcast.link,
            lastUpdate: lastUpdate,
            subscriptionDate: subscriptionDate,
            queueAllEpisodes: queueAllEpisodes,
            cacheAllEpisodes: cacheAllEpisodes,
            alwaysTranscribeNewEpisodes: alwaysTranscribeNewEpisodes,
            notifyNewEpisodes: notifyNewEpisodes
          ),
          unsavedEpisodes: Array(storedEpisodes)
        )
      )
  }
}
