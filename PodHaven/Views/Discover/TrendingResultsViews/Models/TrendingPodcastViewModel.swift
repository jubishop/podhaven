// Copyright Justin Bishop, 2025

import Factory
import Foundation
import IdentifiedCollections
import SwiftUI

@Observable @MainActor class TrendingPodcastViewModel {
  @ObservationIgnored @LazyInjected(\.alert) private var alert
  @ObservationIgnored @LazyInjected(\.repo) private var repo
  @ObservationIgnored @LazyInjected(\.navigation) private var navigation
  @ObservationIgnored @LazyInjected(\.refreshManager) private var refreshManager

  // MARK: - State Management6

  private var _isSelecting = false
  var isSelecting: Bool {
    get { _isSelecting }
    set { withAnimation { _isSelecting = newValue } }
  }

  let category: String
  var unsavedPodcast: UnsavedPodcast
  var episodeList = SelectableListUseCase<UnsavedEpisode, GUID>(idKeyPath: \.guid)
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
          unsavedEpisodes: Array(episodeList.allEntries)
        )
        navigation.showPodcast(newPodcastSeries)
      }
    }
  }

  func queueEpisodeOnTop(_ episode: Episode) {
    Task { try await queue.unshift(episode.id) }
  }

  func queueEpisodeAtBottom(_ episode: Episode) {
    Task { try await queue.append(episode.id) }
  }

  func playEpisode(_ episode: Episode) {
    Task {
      try await playManager.load(PodcastEpisode(podcast: podcast, episode: episode))
      await playManager.play()
    }
  }

  func addSelectedEpisodesToTopOfQueue() {
    Task { try await queue.unshift(selectedEpisodeIDs) }
  }

  func addSelectedEpisodesToBottomOfQueue() {
    Task { try await queue.append(selectedEpisodeIDs) }
  }

  func replaceQueue() {
    Task { try await queue.replace(selectedEpisodeIDs) }
  }

  func replaceQueueAndPlay() {
    Task {
      if let firstEpisode = episodeList.selectedEntries.first {
        try await playManager.load(PodcastEpisode(podcast: podcast, episode: firstEpisode))
        await playManager.play()
        let allExceptFirst = episodeList.selectedEntries.dropFirst()
        try await queue.replace(allExceptFirst.map(\.id))
      }
    }
  }

  // MARK: - Private Helpers

  private func fetchFeed() async throws {
    let podcastFeed = try await PodcastFeed.parse(unsavedPodcast.feedURL)
    self.podcastFeed = podcastFeed
    unsavedPodcast = try podcastFeed.toUnsavedPodcast(subscribed: false, lastUpdate: Date.epoch)
    episodeList.allEntries = IdentifiedArray(
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
