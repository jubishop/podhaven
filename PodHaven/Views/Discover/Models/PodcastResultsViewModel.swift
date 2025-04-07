// Copyright Justin Bishop, 2025

import Factory
import Foundation
import GRDB
import IdentifiedCollections
import SwiftUI

@Observable @MainActor
class PodcastResultsViewModel: QueueableSelectableListModel, UnsavedPodcastQueueableModel {
  @ObservationIgnored @LazyInjected(\.alert) private var alert
  @ObservationIgnored @LazyInjected(\.navigation) private var navigation
  @ObservationIgnored @LazyInjected(\.observatory) private var observatory
  @ObservationIgnored @LazyInjected(\.refreshManager) private var refreshManager
  @ObservationIgnored @LazyInjected(\.repo) private var repo

  // MARK: - State Management

  private var _isSelecting = false
  var isSelecting: Bool {
    get { _isSelecting }
    set { withAnimation { _isSelecting = newValue } }
  }
  var unplayedOnly: Bool = false

  var subscribable: Bool = false
  let searchedText: String

  var unsavedPodcast: UnsavedPodcast
  var episodeList = SelectableListUseCase<UnsavedEpisode, GUID>(idKeyPath: \.guid)
  var unsavedEpisodes: [UnsavedEpisode] { episodeList.allEntries.elements }

  private var existingPodcastSeries: PodcastSeries?
  private var podcastFeed: PodcastFeed?

  // MARK: - Initialization

  init(searchedPodcast: SearchedPodcast) {
    self.searchedText = searchedPodcast.searchedText
    self.unsavedPodcast = searchedPodcast.unsavedPodcast
    episodeList.customFilter = { [unowned self] in !self.unplayedOnly || !$0.completed }
  }

  func execute() async {
    do {
      let podcastFeed = try await PodcastFeed.parse(unsavedPodcast.feedURL)
      self.podcastFeed = podcastFeed

      for try await podcastSeries in observatory.podcastSeries(unsavedPodcast.feedURL) {
        if subscribable && existingPodcastSeries == podcastSeries { continue }

        if let podcastSeries = podcastSeries, podcastSeries.podcast.subscribed {
          navigation.showPodcast(.subscribed, podcastSeries)
        }

        existingPodcastSeries = podcastSeries
        if let podcastSeries = existingPodcastSeries {
          unsavedPodcast = try podcastFeed.toUnsavedPodcast(merging: podcastSeries.podcast.unsaved)
        } else {
          unsavedPodcast = try podcastFeed.toUnsavedPodcast()
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

  // MARK: - EpisodeUpsertable

  func upsert(_ episode: UnsavedEpisode) async throws -> PodcastEpisode {
    try await repo.upsertPodcastEpisode(
      UnsavedPodcastEpisode(
        unsavedPodcast: unsavedPodcast,
        unsavedEpisode: episode
      )
    )
  }

  // MARK: - QueueableSelectableListModel

  func upsertSelectedEpisodes() async throws -> [PodcastEpisode] {
    try await repo.upsertPodcastEpisodes(
      episodeList.selectedEntries.map { unsavedEpisode in
        UnsavedPodcastEpisode(
          unsavedPodcast: unsavedPodcast,
          unsavedEpisode: unsavedEpisode
        )
      }
    )
  }

  // MARK: - Public Functions

  func subscribe() {
    guard subscribable
    else { return }

    Task {
      do {
        if let podcastSeries = existingPodcastSeries, let podcastFeed = self.podcastFeed {
          var podcast = podcastSeries.podcast
          podcast.subscribed = true
          let updatedPodcastSeries = PodcastSeries(
            podcast: podcast,
            episodes: podcastSeries.episodes
          )
          try await refreshManager.updateSeriesFromFeed(
            podcastSeries: updatedPodcastSeries,
            podcastFeed: podcastFeed
          )
          navigation.showPodcast(.subscribed, updatedPodcastSeries)
        } else {
          unsavedPodcast.subscribed = true
          unsavedPodcast.lastUpdate = Date()
          let newPodcastSeries = try await repo.insertSeries(
            unsavedPodcast,
            unsavedEpisodes: unsavedEpisodes
          )
          navigation.showPodcast(.subscribed, newPodcastSeries)
        }
      } catch {
        alert.andReport(error)
      }
    }
  }
}
