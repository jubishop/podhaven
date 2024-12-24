// Copyright Justin Bishop, 2024

import Foundation


enum Helpers {
  static func loadSeries() async throws -> PodcastSeries? {
    let parseResult = await PodcastFeed.parse(
      Bundle.main.url(
        forResource: "pod_save_america",
        withExtension: "rss"
      )!
    )
    guard case .success(let feedResult) = parseResult,
      let unsavedPodcast = feedResult.toUnsavedPodcast(
        oldFeedURL: URL(string: "https://jubi.com")!,
        oldTitle: "Pod Save America"
      )
    else {
      throw FeedError.failedParse("Could not load pod_save_america")
    }
    return try await Repo.shared.insertSeries(
      unsavedPodcast,
      unsavedEpisodes: feedResult.items.map {
        $0.toUnsavedEpisode()
      }
    )
  }
}
