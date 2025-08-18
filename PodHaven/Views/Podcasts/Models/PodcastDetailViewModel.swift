// Copyright Justin Bishop, 2025

import FactoryKit
import Foundation
import GRDB
import IdentifiedCollections
import Logging
import SwiftUI

@Observable @MainActor
class PodcastDetailViewModel:
  QueueableSelectableEpisodeList,
  PodcastQueueableModel
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
      episodeList.filterMethod = currentFilterMethod.filterMethod(for: Episode.self)
    }
  }

  var displayAboutSection: Bool = false

  var episodeList = SelectableListUseCase<Episode, Episode.ID>(idKeyPath: \.id)
  var podcast: Podcast { podcastSeries.podcast }

  var mostRecentEpisodeDate: Date {
    podcastSeries.episodes.first?.pubDate ?? Date.epoch
  }

  private var _podcastSeries: PodcastSeries
  private var podcastSeries: PodcastSeries {
    get { _podcastSeries }
    set {
      _podcastSeries = newValue
      episodeList.allEntries = IdentifiedArray(uniqueElements: newValue.episodes)
    }
  }

  // MARK: - Initialization

  init(podcast: Podcast) {
    self._podcastSeries = PodcastSeries(podcast: podcast)
    episodeList.filterMethod = currentFilterMethod.filterMethod(for: Episode.self)
  }

  func execute() async {
    do {
      if podcastSeries.podcast.lastUpdate < 15.minutesAgo,
        let podcastSeries = try await repo.podcastSeries(podcastSeries.id)
      {
        self.podcastSeries = podcastSeries
        try await refreshSeries()
      }

      for try await podcastSeries in observatory.podcastSeries(podcast.id) {
        guard let podcastSeries = podcastSeries
        else {
          throw ObservatoryError.recordNotFound(type: PodcastSeries.self, id: podcast.id.rawValue)
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
    PodcastEpisode(podcast: podcast, episode: episode)
  }

  // MARK: - QueueableSelectableEpisodeList

  var selectedPodcastEpisodes: [PodcastEpisode] {
    get async throws {
      selectedEpisodes.map { episode in
        PodcastEpisode(
          podcast: podcast,
          episode: episode
        )
      }
    }
  }

  // MARK: - Public Actions

  func refreshSeries() async throws(RefreshError) {
    try await refreshManager.refreshSeries(podcastSeries: podcastSeries)
  }

  func subscribe() {
    Task { [weak self] in
      guard let self else { return }
      try await repo.markSubscribed(podcast.id)
      navigation.showPodcast(.subscribed, podcastSeries.podcast)
    }
  }

  func unsubscribe() {
    Task { [weak self] in
      guard let self else { return }
      try await repo.markUnsubscribed(podcast.id)
      navigation.showPodcast(.unsubscribed, podcastSeries.podcast)
    }
  }
}
