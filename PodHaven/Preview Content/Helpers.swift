// Copyright Justin Bishop, 2024

import Foundation
import GRDB
import OPML

enum Helpers {
  private static let seriesFiles = [
    "pod_save_america": "https://feeds.simplecast.com/dxZsm5kX",
    "land_of_the_giants": "https://feeds.megaphone.fm/landofthegiants",
    "changelog": "https://changelog.com/podcast/feed",
  ]
  private static let opmlFiles = ["large", "small"]

  static func importPodcasts(
    _ numberNeeded: Int = 20,
    from fileName: String = "large"
  )
    async throws
  {
    let allPodcasts = try await Repo.shared.allPodcasts()
    if allPodcasts.count >= numberNeeded { return }

    let url = Bundle.main.url(
      forResource: fileName,
      withExtension: "opml"
    )!
    let opml = try OPML(file: url)

    let feedManager = FeedManager()
    for entry in opml.entries {
      guard let feedURL = entry.feedURL,
        let feedURL = try? feedURL.convertToValidURL()
      else { continue }
      if allPodcasts[id: feedURL] != nil { continue }
      await feedManager.addURL(feedURL)
    }

    var numberRemaining = numberNeeded - allPodcasts.count
    for await feedResult in await feedManager.feeds() {
      switch feedResult {
      case .success(let feedData):
        if let feedURL = feedData.feed.feedURL, let title = feedData.feed.title,
          let unsavedPodcast = feedData.feed.toUnsavedPodcast(
            oldFeedURL: feedURL,
            oldTitle: title
          ),
          (try? await Repo.shared.insertSeries(
            unsavedPodcast,
            unsavedEpisodes: feedData.feed.items.map {
              try $0.toUnsavedEpisode()
            }
          )) != nil
        {
          numberRemaining -= 1
        }
      case .failure(_):
        continue
      }
      let remainingFeeds = await feedManager.remainingFeeds
      if numberRemaining <= 0 || remainingFeeds <= 0 { break }
    }
  }

  static func loadSeries(fileName: String = seriesFiles.keys.randomElement()!)
    async throws -> PodcastSeries
  {
    if let podcastSeries = try? await Repo.shared.db.read({ db in
      try Podcast
        .including(all: Podcast.episodes)
        .shuffled()
        .asRequest(of: PodcastSeries.self)
        .fetchOne(db)
    }) {
      return podcastSeries
    }
    let parseResult = await PodcastFeed.parse(
      Bundle.main.url(forResource: fileName, withExtension: "rss")!
    )
    guard case .success(let feedResult) = parseResult,
      let unsavedPodcast = feedResult.toUnsavedPodcast(
        oldFeedURL: URL(string: seriesFiles[fileName]!)!,
        oldTitle: fileName
      )
    else { throw DBError.seriesNotFound(0) }
    return try await Repo.shared.insertSeries(
      unsavedPodcast,
      unsavedEpisodes: feedResult.items.map {
        try $0.toUnsavedEpisode()
      }
    )
  }

  static func loadPodcastEpisode() async throws -> PodcastEpisode {
    if let podcastEpisode = try? await Repo.shared.db.read({ db in
      try Episode
        .including(required: Episode.podcast)
        .shuffled()
        .asRequest(of: PodcastEpisode.self)
        .fetchOne(db)
    }) {
      return podcastEpisode
    }
    let podcastSeries = try! await loadSeries()
    let episode = podcastSeries.episodes.randomElement()!
    return PodcastEpisode(
      podcast: podcastSeries.podcast,
      episode: episode
    )
  }

  static func populateQueue(queueSize: Int = 20) async throws {
    var allPodcastSeries: [PodcastSeries] = []
    for seriesFile in seriesFiles.keys {
      if let podcastSeries = try? await loadSeries(fileName: seriesFile) {
        allPodcastSeries.append(podcastSeries)
      }
    }
    let currentSize: Int = min(
      try await Repo.shared.db.read { db in
        try Episode.filter(AppDB.queueOrderColumn != nil).fetchCount(db)
      },
      queueSize
    )
    for _ in currentSize...queueSize {
      let episode = allPodcastSeries.randomElement()!.episodes.randomElement()!
      try await Repo.shared.appendToQueue(episode.id)
    }
  }
}
