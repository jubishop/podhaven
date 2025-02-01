// Copyright Justin Bishop, 2025

import Factory
import Foundation

@Observable @MainActor class TrendingItemDetailViewModel {
  @ObservationIgnored @LazyInjected(\.repo) private var repo
  @ObservationIgnored @LazyInjected(\.navigation) private var navigation
  @ObservationIgnored @LazyInjected(\.refreshManager) private var refreshManager

  let category: String
  var unsavedPodcast: UnsavedPodcast
  var unsavedEpisodes: [UnsavedEpisode] = []

  private var existingPodcastSeries: PodcastSeries?
  private var podcastFeed: PodcastFeed?

  init(category: String, unsavedPodcast: UnsavedPodcast) {
    self.category = category
    self.unsavedPodcast = unsavedPodcast
  }

  func fetchFeed() async throws {
    let podcastFeed = try await PodcastFeed.parse(unsavedPodcast.feedURL)
    self.podcastFeed = podcastFeed
    unsavedPodcast = try podcastFeed.toUnsavedPodcast(subscribed: false)
    unsavedEpisodes = podcastFeed.toUnsavedEpisodes()

    existingPodcastSeries = try await repo.podcastSeries(unsavedPodcast.feedURL)
    if let podcastSeries = existingPodcastSeries, podcastSeries.podcast.subscribed {
      navigation.showPodcast(podcastSeries)
    }
  }

  func subscribe() async throws {
    if let podcastSeries = existingPodcastSeries, let podcastFeed = self.podcastFeed {
      var podcast = podcastSeries.podcast
      podcast.subscribed = true
      let updatedPodcastSeries = PodcastSeries(podcast: podcast, episodes: podcastSeries.episodes)
      try await refreshManager.updateSeriesFromFeed(
        podcastSeries: updatedPodcastSeries,
        podcastFeed: podcastFeed
      )
      navigation.showPodcast(updatedPodcastSeries)
    } else {
      unsavedPodcast.subscribed = true
      let newPodcastSeries = try await repo.insertSeries(
        unsavedPodcast,
        unsavedEpisodes: unsavedEpisodes
      )
      navigation.showPodcast(newPodcastSeries)
    }
  }
}
