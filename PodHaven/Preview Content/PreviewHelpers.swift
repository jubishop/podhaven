// Copyright Justin Bishop, 2025

import Factory
import Foundation
import GRDB

enum PreviewHelpers {
  private static let seriesFiles = [
    "pod_save_america": "https://feeds.simplecast.com/dxZsm5kX",
    "land_of_the_giants": "https://feeds.megaphone.fm/landofthegiants",
    "changelog": "https://changelog.com/podcast/feed",
  ]
  private static let opmlFiles = ["large", "small"]

  static func importPodcasts(_ number: Int = 20, from fileName: String = "large") async throws {
    let repo = Container.shared.repo()
    let allPodcasts = try await repo.allPodcasts()
    if allPodcasts.count >= number { return }

    let url = Bundle.main.url(
      forResource: fileName,
      withExtension: "opml"
    )!
    let opml = try await PodcastOPML.parse(url)

    let feedManager = Container.shared.feedManager()
    for outline in opml.body.outlines {
      guard let feedURL = try? outline.xmlUrl.convertToValidURL()
      else { continue }
      if allPodcasts[id: feedURL] != nil { continue }
      await feedManager.addURL(feedURL)
    }

    var numberRemaining = number - allPodcasts.count
    for await feedResult in await feedManager.feeds() {
      switch feedResult {
      case .success(let podcastFeed):
        if (try? await repo.insertSeries(
          try podcastFeed.toUnsavedPodcast(),
          unsavedEpisodes: podcastFeed.episodes.map { try $0.toUnsavedEpisode() }
        )) != nil {
          numberRemaining -= 1
        }
      case .failure(_):
        continue
      }
      let remainingFeeds = await feedManager.remainingFeeds
      if numberRemaining <= 0 || remainingFeeds <= 0 { break }
    }
  }

  static func loadSeries(fileName: String = seriesFiles.keys.randomElement()!) async throws
    -> PodcastSeries
  {
    let repo = Container.shared.repo()
    if let podcastSeries = try? await repo.db.read({ db in
      try Podcast
        .including(all: Podcast.episodes)
        .shuffled()
        .asRequest(of: PodcastSeries.self)
        .fetchOne(db)
    }) {
      return podcastSeries
    }
    let podcastFeed = try await PodcastFeed.parse(
      Bundle.main.url(forResource: fileName, withExtension: "rss")!
    )
    let unsavedPodcast = try podcastFeed.toUnsavedPodcast()
    return try await repo.insertSeries(
      unsavedPodcast,
      unsavedEpisodes: podcastFeed.episodes.map { try $0.toUnsavedEpisode() }
    )
  }

  static func loadPodcast() async throws -> Podcast {
    let repo = Container.shared.repo()
    if let podcast = try? await repo.db.read({ db in
      try Podcast
        .all()
        .shuffled()
        .fetchOne(db)
    }) {
      return podcast
    }
    let podcastSeries = try await loadSeries()
    return podcastSeries.podcast
  }

  static func loadPodcastEpisode() async throws -> PodcastEpisode {
    let repo = Container.shared.repo()
    if let podcastEpisode = try? await repo.db.read({ db in
      try Episode
        .including(required: Episode.podcast)
        .shuffled()
        .asRequest(of: PodcastEpisode.self)
        .fetchOne(db)
    }) {
      return podcastEpisode
    }
    let podcastSeries = try await loadSeries()
    let episode = podcastSeries.episodes.randomElement()!
    return PodcastEpisode(podcast: podcastSeries.podcast, episode: episode)
  }

  static func populateQueue(queueSize: Int = 20) async throws {
    let repo = Container.shared.repo()
    let queue = Container.shared.queue()
    var allPodcastSeries: [PodcastSeries] = []
    for seriesFile in seriesFiles.keys {
      if let podcastSeries = try? await loadSeries(fileName: seriesFile) {
        allPodcastSeries.append(podcastSeries)
      }
    }
    let currentSize: Int = min(
      try await repo.db.read { db in
        try Episode.filter(Schema.queueOrderColumn != nil).fetchCount(db)
      },
      queueSize
    )
    for _ in currentSize...queueSize {
      let episode = allPodcastSeries.randomElement()!.episodes.randomElement()!
      try await queue.append(episode.id)
    }
  }

  static func loadTrendingResult() async throws -> TrendingResult {
    try await SearchService.parseForPreview(
      try Data(
        contentsOf: Bundle.main.url(forResource: "trending_in_news", withExtension: "json")!
      )
    )
  }

  static func loadFeedResult() async throws -> TrendingResult.FeedResult {
    try await loadTrendingResult().feeds.randomElement()!
  }
}
