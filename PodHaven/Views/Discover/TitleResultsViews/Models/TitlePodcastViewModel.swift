// Copyright Justin Bishop, 2025

import Factory
import Foundation
import GRDB
import IdentifiedCollections
import SwiftUI

@Observable @MainActor
class TitlePodcastViewModel:
  UnsavedEpisodeQueueableSelectableListModel,
  UnsavedPodcastQueueableModel
{
  @ObservationIgnored @LazyInjected(\.alert) private var alert
  @ObservationIgnored @LazyInjected(\.navigation) private var navigation
  @ObservationIgnored @LazyInjected(\.observatory) private var observatory
  @ObservationIgnored @LazyInjected(\.playManager) private var playManager
  @ObservationIgnored @LazyInjected(\.queue) private var queue
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
  let searchText: String
  var unsavedPodcast: UnsavedPodcast
  var episodeList = SelectableListUseCase<UnsavedEpisode, GUID>(idKeyPath: \.guid)

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

      for try await podcastSeries in observatory.podcastSeries(unsavedPodcast.feedURL) {
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

}
