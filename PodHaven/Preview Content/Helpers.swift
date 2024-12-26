// Copyright Justin Bishop, 2024

import Foundation
import GRDB

enum Helpers {
  private static let seriesFiles = ["pod_save_america", "land_of_the_giants"]

  static func loadSeries(fileName: String = seriesFiles.randomElement()!)
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
    let fileName = ["pod_save_america", "land_of_the_giants"].randomElement()!
    let parseResult = await PodcastFeed.parse(
      Bundle.main.url(forResource: fileName, withExtension: "rss")!
    )
    guard case .success(let feedResult) = parseResult,
      let unsavedPodcast = feedResult.toUnsavedPodcast(
        oldFeedURL: URL(string: "https://jubi.com")!,
        oldTitle: "Pod Save America"
      )
    else { throw DBError.seriesNotFound(0) }
    return try await Repo.shared.insertSeries(
      unsavedPodcast,
      unsavedEpisodes: feedResult.items.map {
        $0.toUnsavedEpisode()
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

  static func populateQueue(queueSize: Int = 50) async throws {
    var allPodcastSeries: [PodcastSeries] = []
    for seriesFile in seriesFiles {
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
