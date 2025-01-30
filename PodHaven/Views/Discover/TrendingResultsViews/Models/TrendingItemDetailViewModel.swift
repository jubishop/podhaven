// Copyright Justin Bishop, 2025

import Factory
import Foundation

@Observable @MainActor class TrendingItemDetailViewModel {
  @ObservationIgnored @LazyInjected(\.repo) private var repo
  @ObservationIgnored @LazyInjected(\.navigation) private var navigation

  let category: String
  let feedResult: TrendingResult.FeedResult
  var unsavedPodcast: UnsavedPodcast
  var unsavedEpisodes: [UnsavedEpisode] = []

  init(category: String, unsavedPodcast: UnsavedPodcast) {
    self.category = category
    self.unsavedPodcast = unsavedPodcast
  }

  func fetchFeed() async throws {
    let podcastFeed = try await PodcastFeed.parse(unsavedPodcast.feedURL)
    unsavedPodcast = try podcastFeed.toUnsavedPodcast(merging: unsavedPodcast)
    unsavedEpisodes = podcastFeed.toUnsavedEpisodes()
  }

  func subscribe() async throws {
    var unsavedPodcast: UnsavedPodcast = self.unsavedPodcast
    unsavedPodcast.subscribed = true

    let podcastSeries = try await repo.insertSeries(
      unsavedPodcast,
      unsavedEpisodes: unsavedEpisodes
    )
    navigation.showPodcast(podcastSeries)
  }
}
