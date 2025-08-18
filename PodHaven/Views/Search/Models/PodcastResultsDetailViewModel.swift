// Copyright Justin Bishop, 2025

import FactoryKit
import Foundation
import GRDB
import IdentifiedCollections
import SwiftUI

@Observable @MainActor
class PodcastResultsDetailViewModel:
  QueueableSelectableEpisodeList,
  PodcastQueueableModel
{
  @ObservationIgnored @DynamicInjected(\.alert) private var alert
  @ObservationIgnored @DynamicInjected(\.navigation) private var navigation
  @ObservationIgnored @DynamicInjected(\.observatory) private var observatory
  @ObservationIgnored @DynamicInjected(\.refreshManager) private var refreshManager
  @ObservationIgnored @DynamicInjected(\.repo) private var repo

  private static let log = Log.as(LogSubsystem.SearchView.podcastDetail)

  // MARK: - Data

  let searchedText: String
  var unsavedPodcast: UnsavedPodcast

  // MARK: - State Management

  var currentFilterMethod: EpisodeFilterMethod = .all {
    didSet {
      episodeList.filterMethod = currentFilterMethod.filterMethod(for: UnsavedEpisode.self)
    }
  }

  var subscribable: Bool = false
  var displayAboutSection: Bool = false

  var episodeList = SelectableListUseCase<UnsavedEpisode, GUID>(idKeyPath: \.guid)
  private var existingPodcastSeries: PodcastSeries?
  private var podcastFeed: PodcastFeed?

  var mostRecentEpisodeDate: Date {
    episodeList.allEntries.first?.pubDate ?? Date.epoch
  }

  // MARK: - Initialization

  init(searchedPodcast: SearchedPodcast) {
    self.searchedText = searchedPodcast.searchedText
    self.unsavedPodcast = searchedPodcast.unsavedPodcast
    episodeList.filterMethod = currentFilterMethod.filterMethod(for: UnsavedEpisode.self)
  }

  func execute() async {
    Self.log.debug("execute: \(searchedText)")
    do {
      let podcastFeed = try await PodcastFeed.parse(unsavedPodcast.feedURL)
      self.podcastFeed = podcastFeed

      for try await podcastSeries in observatory.podcastSeries(podcastFeed.updatedFeedURL) {
        Self.log.debug(
          "observed existing podcastSeries: \(String(describing: podcastSeries?.toString))"
        )

        if subscribable && existingPodcastSeries == podcastSeries { continue }

        if let podcastSeries = podcastSeries, podcastSeries.podcast.subscribed {
          navigation.showPodcast(.subscribed, podcastSeries.podcast)
        }

        existingPodcastSeries = podcastSeries
        if let podcastSeries = existingPodcastSeries {
          unsavedPodcast = try podcastFeed.toUnsavedPodcast(merging: podcastSeries.podcast.unsaved)
        } else {
          unsavedPodcast = try podcastFeed.toUnsavedPodcast()
        }

        episodeList.allEntries = podcastFeed.toEpisodeArray(merging: existingPodcastSeries)
        subscribable = true
      }
    } catch {
      Self.log.error(error)
      if !ErrorKit.isRemarkable(error) { return }
      alert(ErrorKit.message(for: error))
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

  // MARK: - Public Functions

  func subscribe() {
    guard subscribable
    else { return }

    Task { [weak self] in
      guard let self else { return }
      do {
        if let podcastSeries = existingPodcastSeries, let podcastFeed = podcastFeed {
          var podcast = podcastSeries.podcast
          podcast.subscriptionDate = Date()
          let updatedPodcastSeries = PodcastSeries(
            podcast: podcast,
            episodes: podcastSeries.episodes
          )
          try await refreshManager.updateSeriesFromFeed(
            podcastSeries: updatedPodcastSeries,
            podcastFeed: podcastFeed
          )
          navigation.showPodcast(.subscribed, updatedPodcastSeries.podcast)
        } else {
          unsavedPodcast.subscriptionDate = Date()
          unsavedPodcast.lastUpdate = Date()
          let newPodcastSeries = try await repo.insertSeries(
            unsavedPodcast,
            unsavedEpisodes: episodeList.allEntries.elements
          )
          navigation.showPodcast(.subscribed, newPodcastSeries.podcast)
        }
      } catch {
        Self.log.error(error)
        alert(ErrorKit.message(for: error))
      }
    }
  }
}
