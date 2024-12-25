// Copyright Justin Bishop, 2024

import Foundation

enum Helpers {
  static func loadSeries()
    async throws -> PodcastSeries?
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
    else { return nil }
    return try await Repo.shared.insertSeries(
      unsavedPodcast,
      unsavedEpisodes: feedResult.items.map {
        $0.toUnsavedEpisode()
      }
    )
  }

  static func loadPodcastEpisode() async throws -> PodcastEpisode? {
    if let podcastEpisode = try? await Repo.shared.db.read({ db in
      try Episode
        .including(required: Episode.podcast)
        .shuffled()
        .asRequest(of: PodcastEpisode.self)
        .fetchOne(db)
    }) {
      return podcastEpisode
    }
    guard let podcastSeries = try? await loadSeries(),
      let episode = podcastSeries.episodes.randomElement()
    else { return nil }
    return PodcastEpisode(
      podcast: podcastSeries.podcast,
      episode: episode
    )
  }
}
