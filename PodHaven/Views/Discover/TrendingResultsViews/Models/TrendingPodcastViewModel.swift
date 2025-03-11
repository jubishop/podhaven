// Copyright Justin Bishop, 2025

import Factory
import Foundation
import IdentifiedCollections
import SwiftUI

@Observable @MainActor class TrendingPodcastViewModel {
  @ObservationIgnored @LazyInjected(\.alert) private var alert
  @ObservationIgnored @LazyInjected(\.navigation) private var navigation
  @ObservationIgnored @LazyInjected(\.playManager) private var playManager
  @ObservationIgnored @LazyInjected(\.queue) private var queue
  @ObservationIgnored @LazyInjected(\.refreshManager) private var refreshManager
  @ObservationIgnored @LazyInjected(\.repo) private var repo

  // MARK: - State Management6

  private var _isSelecting = false
  var isSelecting: Bool {
    get { _isSelecting }
    set { withAnimation { _isSelecting = newValue } }
  }

  var subscribable: Bool = false
  let category: String
  var unsavedPodcast: UnsavedPodcast
  var episodeList = SelectableListUseCase<UnsavedEpisode, GUID>(idKeyPath: \.guid)
  var filteredUnsavedPodcastEpisodes: [UnsavedPodcastEpisode] {
    episodeList.selectedEntries.map { unsavedEpisode in
      UnsavedPodcastEpisode(
        unsavedPodcast: unsavedPodcast,
        unsavedEpisode: unsavedEpisode
      )
    }
  }

  private var existingPodcastSeries: PodcastSeries?
  private var podcastFeed: PodcastFeed?

  // MARK: - Initialization

  init(category: String, unsavedPodcast: UnsavedPodcast) {
    self.category = category
    self.unsavedPodcast = unsavedPodcast
  }

  func execute() async {
    do {
      existingPodcastSeries = try await repo.podcastSeries(unsavedPodcast.feedURL)
      if let podcastSeries = existingPodcastSeries, podcastSeries.podcast.subscribed {
        navigation.showPodcast(podcastSeries)
      }

      let podcastFeed = try await PodcastFeed.parse(unsavedPodcast.feedURL)
      unsavedPodcast = try podcastFeed.toUnsavedPodcast(merging: existingPodcastSeries?.podcast)
      episodeList.allEntries = IdentifiedArray(
        uniqueElements: try podcastFeed.episodes.map { episodeFeed in
          try episodeFeed.toUnsavedEpisode(
            merging: existingPodcastSeries?.episodes[id: episodeFeed.guid]
          )
        },
        id: \.guid
      )

      subscribable = true
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
    //    Task { try await queue.unshift(episode.id) }
  }

  func queueEpisodeAtBottom(_ episode: Episode) {
    //    Task { try await queue.append(episode.id) }
  }

  func playEpisode(_ episode: Episode) {
    //    Task {
    //      try await playManager.load(PodcastEpisode(podcast: podcast, episode: episode))
    //      await playManager.play()
    //    }
  }

  func addSelectedEpisodesToTopOfQueue() {
    Task {
      let podcastEpisodes = try await repo.upsertPodcastEpisodes(filteredUnsavedPodcastEpisodes)
      try await queue.unshift(podcastEpisodes.map(\.id))
    }
  }

  func addSelectedEpisodesToBottomOfQueue() {
    Task {
      let podcastEpisodes = try await repo.upsertPodcastEpisodes(filteredUnsavedPodcastEpisodes)
      try await queue.append(podcastEpisodes.map(\.id))
    }
  }

  func replaceQueue() {
    Task {
      let podcastEpisodes = try await repo.upsertPodcastEpisodes(filteredUnsavedPodcastEpisodes)
      try await queue.replace(podcastEpisodes.map(\.id))
    }
  }

  func replaceQueueAndPlay() {
    Task {
      let podcastEpisodes = try await repo.upsertPodcastEpisodes(filteredUnsavedPodcastEpisodes)
      if let firstPodcastEpisode = podcastEpisodes.first {
        try await playManager.load(firstPodcastEpisode)
        await playManager.play()
        let allExceptFirstPodcastEpisode = podcastEpisodes.dropFirst()
        try await queue.replace(allExceptFirstPodcastEpisode.map(\.id))
      }
    }
  }
}
