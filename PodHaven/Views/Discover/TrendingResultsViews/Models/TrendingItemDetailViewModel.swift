// Copyright Justin Bishop, 2025

import Factory
import Foundation

@Observable @MainActor class TrendingItemDetailViewModel {
  let category: String
  let feedResult: TrendingResult.FeedResult
  var unsavedPodcast: UnsavedPodcast?
  var unsavedEpisodes: [UnsavedEpisode] = []

  init(category: String, feedResult: TrendingResult.FeedResult) {
    self.category = category
    self.feedResult = feedResult
  }

  func fetchFeed() async throws {
    let feedManager = Container.shared.feedManager()
    let feedTask = await feedManager.addURL(feedResult.url)
    let feedResult = await feedTask.feedParsed()
    switch feedResult {
    case .failure(let error):
      throw error
    case .success(let podcastFeed):
      self.unsavedPodcast = try podcastFeed.toUnsavedPodcast()
      self.unsavedEpisodes = podcastFeed.episodes.compactMap { episodeFeed in
        try? episodeFeed.toUnsavedEpisode()
      }
    }
  }
}
