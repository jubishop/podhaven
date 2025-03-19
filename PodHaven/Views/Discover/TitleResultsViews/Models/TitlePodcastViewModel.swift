// Copyright Justin Bishop, 2025

import Factory
import Foundation
import GRDB
import IdentifiedCollections
import SwiftUI

@Observable @MainActor
class TitlePodcastViewModel: QueueableSelectableList, EpisodeQueueable {
  @ObservationIgnored @LazyInjected(\.alert) private var alert
  @ObservationIgnored @LazyInjected(\.navigation) private var navigation
  @ObservationIgnored @LazyInjected(\.playManager) private var playManager
  @ObservationIgnored @LazyInjected(\.queue) private var queue
  @ObservationIgnored @LazyInjected(\.refreshManager) private var refreshManager
  @ObservationIgnored @LazyInjected(\.repo) private var repo

  // MARK: - Episode-able protocols

  typealias EpisodeType = UnsavedEpisode

  // MARK: - State Management

  private var _isSelecting = false
  var isSelecting: Bool {
    get { _isSelecting }
    set { withAnimation { _isSelecting = newValue } }
  }
  var unplayedOnly: Bool = false

  var subscribable: Bool = false
  let searchText: String
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

  init(titlePodcast: SearchedPodcastByTitle) {
    self.searchText = titlePodcast.searchText
    self.unsavedPodcast = titlePodcast.unsavedPodcast
    episodeList.customFilter = { [unowned self] in !self.unplayedOnly || !$0.completed }
  }

  func execute() async {
    do {
      let podcastFeed = try await PodcastFeed.parse(unsavedPodcast.feedURL)

      let observer =
        ValueObservation
        .tracking(
          Podcast
            .filter(Schema.feedURLColumn == unsavedPodcast.feedURL)
            .including(all: Podcast.episodes)
            .asRequest(of: PodcastSeries.self)
            .fetchOne
        )
        .removeDuplicates()

      for try await podcastSeries in observer.values(in: repo.db) {
        if subscribable && existingPodcastSeries == podcastSeries { continue }
        if let podcastSeries = podcastSeries, podcastSeries.podcast.subscribed {
          navigation.showPodcast(podcastSeries)
        }

        existingPodcastSeries = podcastSeries
        if let podcastSeries = existingPodcastSeries {
          unsavedPodcast = try podcastFeed.toUnsavedPodcast(merging: podcastSeries.podcast.unsaved)
        } else {
          unsavedPodcast = try podcastFeed.toUnsavedPodcast(
            subscribed: false,
            lastUpdate: Date.epoch
          )
        }

        episodeList.allEntries = IdentifiedArray(
          uniqueElements: try podcastFeed.episodes.map { episodeFeed in
            try episodeFeed.toUnsavedEpisode(
              merging: existingPodcastSeries?.episodes[id: episodeFeed.guid]
            )
          },
          id: \.guid
        )

        subscribable = true
      }
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

  func queueEpisodeOnTop(_ episode: UnsavedEpisode) {
    Task {
      let podcastEpisode = try await repo.upsertPodcastEpisode(
        UnsavedPodcastEpisode(
          unsavedPodcast: unsavedPodcast,
          unsavedEpisode: episode
        )
      )
      try await queue.unshift(podcastEpisode.id)
    }
  }

  func queueEpisodeAtBottom(_ episode: UnsavedEpisode) {
    Task {
      let podcastEpisode = try await repo.upsertPodcastEpisode(
        UnsavedPodcastEpisode(
          unsavedPodcast: unsavedPodcast,
          unsavedEpisode: episode
        )
      )
      try await queue.append(podcastEpisode.id)
    }
  }

  func playEpisode(_ episode: UnsavedEpisode) {
    Task {
      let podcastEpisode = try await repo.upsertPodcastEpisode(
        UnsavedPodcastEpisode(
          unsavedPodcast: unsavedPodcast,
          unsavedEpisode: episode
        )
      )
      try await playManager.load(podcastEpisode)
      await playManager.play()
    }
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
