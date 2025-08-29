// Copyright Justin Bishop, 2025

import FactoryKit
import Foundation
import GRDB
import IdentifiedCollections
import SwiftUI

@Observable @MainActor
class PodcastResultsDetailViewModel:
  PodcastDetailViewableModel,
  ManagingEpisodesModel,
  SelectableEpisodeListModel
{
  @ObservationIgnored @DynamicInjected(\.alert) private var alert
  @ObservationIgnored @DynamicInjected(\.navigation) private var navigation
  @ObservationIgnored @DynamicInjected(\.observatory) private var observatory
  @ObservationIgnored @DynamicInjected(\.refreshManager) private var refreshManager
  @ObservationIgnored @DynamicInjected(\.repo) private var repo

  private static let log = Log.as(LogSubsystem.SearchView.podcast)

  // MARK: - Data

  let searchedText: String
  var unsavedPodcast: UnsavedPodcast

  // MARK: - State Management

  var currentFilterMethod: EpisodeFilterMethod = .all {
    didSet {
      episodeList.filterMethod = currentFilterMethod.filterMethod(for: UnsavedPodcastEpisode.self)
    }
  }
  var displayAboutSection: Bool = false
  var mostRecentEpisodeDate: Date {
    episodeList.allEntries.first?.pubDate ?? Date.epoch
  }

  private var existingPodcastSeries: PodcastSeries?
  private var podcastFeed: PodcastFeed?

  // MARK: - SelectableEpisodeListModel

  var episodeList = SelectableListUseCase<UnsavedPodcastEpisode, GUID>(
    idKeyPath: \.unsavedEpisode.guid
  )
  private var _isSelecting = false
  var isSelecting: Bool {
    get { _isSelecting }
    set { withAnimation { _isSelecting = newValue } }
  }
  var selectedPodcastEpisodes: [PodcastEpisode] {
    get async throws {
      try await repo.upsertPodcastEpisodes(selectedEpisodes)
    }
  }

  // MARK: - PodcastDetailViewableModel

  var subscribable: Bool = false
  let refreshable: Bool = false
  var podcast: any PodcastDisplayable { unsavedPodcast }

  // MARK: - Initialization

  init(searchedPodcast: SearchedPodcast) {
    self.searchedText = searchedPodcast.searchedText
    self.unsavedPodcast = searchedPodcast.unsavedPodcast
    episodeList.sortMethod = { $0.pubDate > $1.pubDate }
    episodeList.filterMethod = currentFilterMethod.filterMethod(for: UnsavedPodcastEpisode.self)
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
        unsavedPodcast = try podcastFeed.toUnsavedPodcast(merging: podcastSeries?.podcast.unsaved)
        episodeList.allEntries = IdentifiedArray(
          uniqueElements: podcastFeed.toEpisodeArray(merging: existingPodcastSeries)
            .map {
              UnsavedPodcastEpisode(unsavedPodcast: unsavedPodcast, unsavedEpisode: $0)
            },
          id: \.unsavedEpisode.guid
        )
        subscribable = true
      }
    } catch {
      Self.log.error(error)
      if !ErrorKit.isRemarkable(error) { return }
      alert(ErrorKit.message(for: error))
    }
  }

  // MARK: - ManagingEpisodesModel

  func getPodcastEpisode(_ unsavedPodcastEpisode: UnsavedPodcastEpisode) async throws
    -> PodcastEpisode
  {
    try await repo.upsertPodcastEpisode(unsavedPodcastEpisode)
  }

  // MARK: - PodcastDetailViewableModel

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
            unsavedEpisodes: episodeList.allEntries.elements.map(\.unsavedEpisode)
          )
          navigation.showPodcast(.subscribed, newPodcastSeries.podcast)
        }
      } catch {
        Self.log.error(error)
        alert(ErrorKit.message(for: error))
      }
    }
  }

  func unsubscribe() {
    Assert.fatal("Trying to unsubscribe from a PodcastResult?")
  }

  func refreshSeries() async {
    Assert.fatal("Trying to refresh a PodcastResult?")
  }

  func navigationDestination(for episode: UnsavedPodcastEpisode) -> Navigation.Search.Destination {
    .searchedPodcastEpisode(
      SearchedPodcastEpisode(
        searchedText: searchedText,
        episode: episode
      )
    )
  }
}
