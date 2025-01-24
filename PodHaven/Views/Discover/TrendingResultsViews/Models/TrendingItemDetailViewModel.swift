// Copyright Justin Bishop, 2025

import Factory
import Foundation

@Observable @MainActor class TrendingItemDetailViewModel {
  @ObservationIgnored @LazyInjected(\.repo) private var repo
  @ObservationIgnored @LazyInjected(\.navigation) private var navigation

  let category: String
  let feedResult: TrendingResult.FeedResult
  var unsavedPodcast: UnsavedPodcast?
  var unsavedEpisodes: [UnsavedEpisode] = []

  init(category: String, feedResult: TrendingResult.FeedResult) {
    self.category = category
    self.feedResult = feedResult
  }

  @discardableResult
  func fetchFeed() async throws -> UnsavedPodcast {
    let podcastFeed = try await PodcastFeed.parse(feedResult.url)
    let unsavedPodcast = try podcastFeed.toUnsavedPodcast(subscribed: false)
    self.unsavedPodcast = unsavedPodcast
    self.unsavedEpisodes = podcastFeed.toUnsavedEpisodes()
    return unsavedPodcast
  }

  func subscribe() async throws {
    var unsavedPodcast: UnsavedPodcast
    if let fetchedUnsavedPodcast = self.unsavedPodcast {
      unsavedPodcast = fetchedUnsavedPodcast
    } else {
      unsavedPodcast = try await fetchFeed()
    }
    unsavedPodcast.subscribed = true

    let podcastSeries = try await repo.insertSeries(
      unsavedPodcast,
      unsavedEpisodes: unsavedEpisodes
    )
    navigation.showPodcast(podcastSeries)
  }
}
