// Copyright Justin Bishop, 2024

import Foundation

enum Helpers {
  private static let seriesFiles = ["pod_save_america", "land_of_the_giants"]

  static func loadSeries(fileName: String = seriesFiles.randomElement()!)
    async throws -> PodcastSeries?
  {
    let parseResult = await PodcastFeed.parse(
      Bundle.main.url(forResource: fileName, withExtension: "rss")!
    )
    guard case .success(let feedResult) = parseResult,
      let unsavedPodcast = feedResult.toUnsavedPodcast(
        oldFeedURL: URL(string: "https://jubi.com")!,
        oldTitle: "Pod Save America"
      )
    else { throw FeedError.failedParse("Could not load \(fileName)") }
    return try await Repo.shared.insertSeries(
      unsavedPodcast,
      unsavedEpisodes: feedResult.items.map {
        $0.toUnsavedEpisode()
      }
    )
  }
}
