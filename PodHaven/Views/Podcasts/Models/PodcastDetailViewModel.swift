// Copyright Justin Bishop, 2025

import FactoryKit
import Foundation
import GRDB
import IdentifiedCollections
import Logging
import SwiftUI

@Observable @MainActor
class PodcastDetailViewModel:
  PodcastDetailViewableModel,
  PodcastQueueableModel,
  QueueableSelectableListModel
{
  @ObservationIgnored @DynamicInjected(\.alert) private var alert
  @ObservationIgnored @DynamicInjected(\.navigation) private var navigation
  @ObservationIgnored @DynamicInjected(\.observatory) private var observatory
  @ObservationIgnored @DynamicInjected(\.playManager) private var playManager
  @ObservationIgnored @DynamicInjected(\.queue) private var queue
  @ObservationIgnored @DynamicInjected(\.refreshManager) private var refreshManager
  @ObservationIgnored @DynamicInjected(\.repo) private var repo

  private static let log = Log.as(LogSubsystem.PodcastsView.detail)

  // MARK: - State Management

  var currentFilterMethod: EpisodeFilterMethod = .all {
    didSet {
      episodeList.filterMethod = currentFilterMethod.filterMethod(for: PodcastEpisode.self)
    }
  }
  var displayAboutSection: Bool = false
  var mostRecentEpisodeDate: Date {
    podcastSeries.episodes.first?.pubDate ?? Date.epoch
  }

  private var _podcastSeries: PodcastSeries
  private var podcastSeries: PodcastSeries {
    get { _podcastSeries }
    set {
      _podcastSeries = newValue
      episodeList.allEntries = newValue.podcastEpisodes
    }
  }

  // MARK: - QueueableSelectableListModel

  var episodeList = SelectableListUseCase<PodcastEpisode, GUID>(idKeyPath: \.episode.guid)
  private var _isSelecting = false
  var isSelecting: Bool {
    get { _isSelecting }
    set { withAnimation { _isSelecting = newValue } }
  }
  var selectedPodcastEpisodes: [PodcastEpisode] {
    get async throws { selectedEpisodes }
  }

  // MARK: - PodcastDetailViewableModel

  let subscribable: Bool = true
  let refreshable: Bool = true
  var podcast: any PodcastDisplayable { podcastSeries.podcast }

  // MARK: - Initialization

  init(podcast: Podcast) {
    self._podcastSeries = PodcastSeries(podcast: podcast)
    episodeList.filterMethod = currentFilterMethod.filterMethod(for: PodcastEpisode.self)
  }

  func execute() async {
    do {
      if podcastSeries.podcast.lastUpdate < 15.minutesAgo,
        let podcastSeries = try await repo.podcastSeries(podcastSeries.id)
      {
        self.podcastSeries = podcastSeries
        await refreshSeries()
      }

      for try await podcastSeries in observatory.podcastSeries(podcastSeries.id) {
        guard let podcastSeries = podcastSeries
        else {
          throw ObservatoryError.recordNotFound(
            type: PodcastSeries.self,
            id: self.podcastSeries.id.rawValue
          )
        }

        if self.podcastSeries == podcastSeries { continue }
        self.podcastSeries = podcastSeries
      }
    } catch {
      Self.log.error(error)
      if !ErrorKit.isRemarkable(error) { return }
      alert(ErrorKit.message(for: error))
    }
  }

  // MARK: - PodcastQueueableModel

  func getPodcastEpisode(_ episode: Episode) async throws -> PodcastEpisode {
    PodcastEpisode(podcast: podcastSeries.podcast, episode: episode)
  }

  // MARK: - PodcastDetailViewableModel

  func refreshSeries() async {
    do {
      try await refreshManager.refreshSeries(podcastSeries: podcastSeries)
    } catch {
      Self.log.error(error)
      if !ErrorKit.isRemarkable(error) { return }
      alert(ErrorKit.message(for: error))
    }
  }

  func subscribe() {
    Task { [weak self] in
      guard let self else { return }
      try await repo.markSubscribed(podcastSeries.id)
      navigation.showPodcast(.subscribed, podcastSeries.podcast)
    }
  }

  func unsubscribe() {
    Task { [weak self] in
      guard let self else { return }
      try await repo.markUnsubscribed(podcastSeries.id)
      navigation.showPodcast(.unsubscribed, podcastSeries.podcast)
    }
  }

  func navigationDestination(for episode: PodcastEpisode) -> Navigation.Podcasts.Destination {
    .episode(episode)
  }
}
