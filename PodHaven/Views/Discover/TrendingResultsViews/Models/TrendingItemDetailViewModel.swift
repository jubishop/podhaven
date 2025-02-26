// Copyright Justin Bishop, 2025

import Factory
import Foundation
import IdentifiedCollections

@Observable @MainActor class TrendingItemDetailViewModel {
  @ObservationIgnored @LazyInjected(\.alert) private var alert
  @ObservationIgnored @LazyInjected(\.repo) private var repo
  @ObservationIgnored @LazyInjected(\.navigation) private var navigation
  @ObservationIgnored @LazyInjected(\.refreshManager) private var refreshManager

  // MARK: - State Management

  let category: String
  var unsavedPodcast: UnsavedPodcast
  var episodeList = EpisodeListUseCase<UnsavedEpisode, GUID>(idKeyPath: \.guid)
  var subscribable: Bool = false

  private var existingPodcastSeries: PodcastSeries?
  private var podcastFeed: PodcastFeed?

  // MARK: - Initialization

  init(category: String, unsavedPodcast: UnsavedPodcast) {
    self.category = category
    self.unsavedPodcast = unsavedPodcast
  }

  func execute() async {
    do {
      try await fetchFeed()
    } catch {
      alert.andReport(error)
    }
  }

  // MARK: - Public Functions

  func subscribe() {
    Task {
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
        unsavedPodcast.lastUpdate = Date()
        let newPodcastSeries = try await repo.insertSeries(
          unsavedPodcast,
          unsavedEpisodes: Array(episodeList.allEpisodes)
        )
        navigation.showPodcast(newPodcastSeries)
      }
    }
  }

  // MARK: - Private Helpers

  private func fetchFeed() async throws {
    let podcastFeed = try await PodcastFeed.parse(unsavedPodcast.feedURL)
    self.podcastFeed = podcastFeed
    unsavedPodcast = try podcastFeed.toUnsavedPodcast(subscribed: false, lastUpdate: Date.epoch)
    episodeList.allEpisodes = IdentifiedArray(
      uniqueElements: podcastFeed.toUnsavedEpisodes(),
      id: \.guid
    )

    existingPodcastSeries = try await repo.podcastSeries(unsavedPodcast.feedURL)
    if let podcastSeries = existingPodcastSeries, podcastSeries.podcast.subscribed {
      navigation.showPodcast(podcastSeries)
    } else {
      subscribable = true
    }
  }
}
