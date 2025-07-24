// Copyright Justin Bishop, 2025

import FactoryKit
import Foundation
import GRDB
import IdentifiedCollections

enum PreviewHelpers {
  private static let seriesFiles = [
    "pod_save_america": "https://feeds.simplecast.com/dxZsm5kX",
    "land_of_the_giants": "https://feeds.megaphone.fm/landofthegiants",
    "changelog": "https://changelog.com/podcast/feed",
  ]
  private static let opmlFiles = ["large", "small"]

  // MARK: - Full Importing From OPML

  static func importPodcasts(_ number: Int = 20, from fileName: String = "large") async throws {
    let repo = Container.shared.repo()
    let allPodcasts = IdentifiedArray(uniqueElements: try await repo.allPodcasts(), id: \.feedURL)
    if allPodcasts.count >= number { return }

    let url = Bundle.main.url(
      forResource: fileName,
      withExtension: "opml"
    )!
    let opml = try await PodcastOPML.parse(url)

    var remainingPodcasts = number - allPodcasts.count
    let feedManager = Container.shared.feedManager()
    try await withThrowingDiscardingTaskGroup { group in
      for rssFeed in opml.rssFeeds {
        if remainingPodcasts <= 0 { break }
        if allPodcasts[id: rssFeed.feedURL] != nil { continue }
        group.addTask {
          let feedTask = await feedManager.addURL(rssFeed.feedURL)
          let podcastFeed = try await feedTask.feedParsed()
          try await repo.insertSeries(
            try podcastFeed.toUnsavedPodcast(),
            unsavedEpisodes: podcastFeed.episodes.map { try $0.toUnsavedEpisode() }
          )
        }
        remainingPodcasts -= 1
      }
    }
  }

  // MARK: - Loading Podcasts/Episodes

  static func loadAllSeries() async throws -> [PodcastSeries] {
    var allPodcastSeries = [PodcastSeries](capacity: seriesFiles.count)
    for seriesFile in seriesFiles.keys {
      if let podcastSeries = try? await loadSeries(fileName: seriesFile) {
        allPodcastSeries.append(podcastSeries)
      }
    }
    return allPodcastSeries
  }

  static func loadSeries(fileName: String = seriesFiles.keys.randomElement()!) async throws
    -> PodcastSeries
  {
    let podcastFeed = try await PodcastFeed.parse(
      FeedURL(Bundle.main.url(forResource: fileName, withExtension: "rss")!)
    )
    let unsavedPodcast = try podcastFeed.toUnsavedPodcast()

    let repo = Container.shared.repo()
    if let podcastSeries = try? await repo.db.read({ db in
      try Podcast
        .filter { $0.feedURL == unsavedPodcast.feedURL }
        .including(all: Podcast.episodes)
        .asRequest(of: PodcastSeries.self)
        .fetchOne(db)
    }) {
      return podcastSeries
    }

    return try await repo.insertSeries(
      unsavedPodcast,
      unsavedEpisodes: podcastFeed.episodes.map { try $0.toUnsavedEpisode() }
    )
  }

  static func loadPodcast(fileName: String = seriesFiles.keys.randomElement()!) async throws
    -> Podcast
  {
    let podcastSeries = try await loadSeries(fileName: fileName)
    return podcastSeries.podcast
  }

  static func loadPodcastEpisode(fileName: String = seriesFiles.keys.randomElement()!) async throws
    -> PodcastEpisode
  {
    let podcastSeries = try await loadSeries(fileName: fileName)
    let episode = podcastSeries.episodes.randomElement()!
    return PodcastEpisode(podcast: podcastSeries.podcast, episode: episode)
  }

  static func loadEpisodes(fileName: String = seriesFiles.keys.randomElement()!) async throws
    -> IdentifiedArray<GUID, Episode>
  {
    let podcastSeries = try await loadSeries(fileName: fileName)
    return podcastSeries.episodes
  }

  static func loadEpisode(fileName: String = seriesFiles.keys.randomElement()!) async throws
    -> Episode
  {
    let podcastSeries = try await loadSeries(fileName: fileName)
    return podcastSeries.episodes.randomElement()!
  }

  // MARK: - Importing Unsaved Podcasts/Episodes

  static func loadUnsavedPodcastEpisodes(fileName: String = seriesFiles.keys.randomElement()!)
    async throws
    -> (UnsavedPodcast, [UnsavedEpisode])
  {
    let podcastFeed = try await PodcastFeed.parse(
      FeedURL(Bundle.main.url(forResource: fileName, withExtension: "rss")!)
    )
    let unsavedPodcast = try podcastFeed.toUnsavedPodcast()
    return (
      unsavedPodcast,
      try podcastFeed.episodes.map { try $0.toUnsavedEpisode() }
    )
  }

  static func loadUnsavedEpisode(fileName: String = seriesFiles.keys.randomElement()!) async throws
    -> UnsavedEpisode
  {
    let (_, unsavedEpisodes) = try! await PreviewHelpers.loadUnsavedPodcastEpisodes()
    return unsavedEpisodes.randomElement()!
  }

  static func loadUnsavedPodcast(fileName: String = seriesFiles.keys.randomElement()!) async throws
    -> UnsavedPodcast
  {
    let (unsavedPodcast, _) = try! await PreviewHelpers.loadUnsavedPodcastEpisodes()
    return unsavedPodcast
  }

  // MARK: Queue Management

  static func populateQueue(queueSize: Int = 20) async throws {
    let repo = Container.shared.repo()
    var currentSize = try await repo.db.read { db in
      try Episode.all().queued().fetchCount(db)
    }
    if currentSize >= queueSize { return }

    let queue = Container.shared.queue()
    for episode in (try await loadAllSeries()).flatMap({ $0.episodes }) {
      if currentSize >= queueSize { break }
      if !episode.queued {
        try await queue.append(episode.id)
        currentSize += 1
      }
    }
  }

  static func populateCompletedPodcastEpisodes(listSize: Int = 20) async throws {
    let repo = Container.shared.repo()
    var currentSize = try await repo.db.read { db in
      try Episode.all().completed().fetchCount(db)
    }
    if currentSize >= listSize { return }

    for episode in (try await loadAllSeries()).flatMap({ $0.episodes }) {
      if currentSize >= listSize { break }
      if !episode.completed {
        try await repo.markComplete(episode.id)
        currentSize += 1
      }
    }
  }

  // MARK: - Searching

  static func loadTrendingResult() async throws -> TrendingResult {
    try await SearchService.parse(
      try Data(
        contentsOf: Bundle.main.url(forResource: "trending_in_news", withExtension: "json")!
      )
    )
  }

  static func loadTitleResult() async throws -> TitleResult {
    try await SearchService.parse(
      try Data(
        contentsOf: Bundle.main.url(forResource: "hello_bytitle", withExtension: "json")!
      )
    )
  }

  static func loadTermResult() async throws -> TermResult {
    try await SearchService.parse(
      try Data(
        contentsOf: Bundle.main.url(forResource: "hardfork_byterm", withExtension: "json")!
      )
    )
  }

  static func loadPersonResult() async throws -> PersonResult {
    try await SearchService.parse(
      try Data(
        contentsOf: Bundle.main.url(forResource: "ndg_byperson", withExtension: "json")!
      )
    )
  }
}
