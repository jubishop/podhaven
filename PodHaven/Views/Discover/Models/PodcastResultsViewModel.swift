// Copyright Justin Bishop, 2025

import Factory
import Foundation
import GRDB
import IdentifiedCollections
import SwiftUI

@Observable @MainActor
class PodcastResultsViewModel: QueueableSelectableEpisodeList, PodcastQueueableModel {
  @ObservationIgnored @LazyInjected(\.alert) private var alert
  @ObservationIgnored @LazyInjected(\.navigation) private var navigation
  @ObservationIgnored @LazyInjected(\.observatory) private var observatory
  @ObservationIgnored @LazyInjected(\.refreshManager) private var refreshManager
  @ObservationIgnored @LazyInjected(\.repo) private var repo

  // MARK: - State Management

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
    episodeList.filterMethod = { [weak self] in
      guard let self else { return true }
      return !unplayedOnly || !$0.completed
    }
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
      alert("Couldn't execute PodcastResultsViewModel")
    }
  }

  // MARK: - PodcastQueueableModel

  func getPodcastEpisode(_ episode: UnsavedEpisode) async throws -> PodcastEpisode {
    try await repo.upsertPodcastEpisode(
      UnsavedPodcastEpisode(
        unsavedPodcast: unsavedPodcast,
        unsavedEpisode: episode
      )
    )
  }

  func getEpisodeID(_ episode: UnsavedEpisode) async throws -> Episode.ID {
    try await getPodcastEpisode(episode).id
  }

  // MARK: - QueueableSelectableEpisodeList

  var selectedPodcastEpisodes: [PodcastEpisode] {
    get async throws {
      try await repo.upsertPodcastEpisodes(
        selectedEpisodes.map { unsavedEpisode in
          UnsavedPodcastEpisode(
            unsavedPodcast: unsavedPodcast,
            unsavedEpisode: unsavedEpisode
          )
        }
      )
    }
  }

  var selectedEpisodeIDs: [Episode.ID] {
    get async throws {
      try await selectedPodcastEpisodes.map(\.id)
    }
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
        alert("Couldn't subscribe")
      }
    }
  }
}
