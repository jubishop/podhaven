// Copyright Justin Bishop, 2025

import Factory
import Foundation

@Observable @MainActor class TrendingItemDetailViewModel {
  @ObservationIgnored @LazyInjected(\.repo) private var repo
  @ObservationIgnored @LazyInjected(\.navigation) private var navigation

  let category: String
  var unsavedPodcast: UnsavedPodcast
  var unsavedEpisodes: [UnsavedEpisode] = []

  init(category: String, unsavedPodcast: UnsavedPodcast) {
    self.category = category
    self.unsavedPodcast = unsavedPodcast
  }

  func fetchFeed() async throws {
    let podcastFeed = try await PodcastFeed.parse(unsavedPodcast.feedURL)
    unsavedPodcast = try podcastFeed.toUnsavedPodcast(subscribed: false)
    unsavedEpisodes = podcastFeed.toUnsavedEpisodes()

    if let podcastSeries = try await repo.podcastSeries(unsavedPodcast.feedURL),
      podcastSeries.podcast.subscribed
    {
      navigation.showPodcast(podcastSeries)
    }
  }

  func subscribe() async throws {
    unsavedPodcast.subscribed = true

    let podcastSeries = try await repo.insertSeries(
      unsavedPodcast,
      unsavedEpisodes: unsavedEpisodes
    )
    navigation.showPodcast(podcastSeries)
  }
}
