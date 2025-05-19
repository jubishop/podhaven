// Copyright Justin Bishop, 2025

import FactoryKit
import Foundation
import GRDB
import IdentifiedCollections
import SwiftUI

@Observable @MainActor
final class PodcastDetailViewModel: QueueableSelectableEpisodeList, PodcastQueueableModel {
  @ObservationIgnored @DynamicInjected(\.alert) private var alert
  @ObservationIgnored @DynamicInjected(\.navigation) private var navigation
  @ObservationIgnored @DynamicInjected(\.observatory) private var observatory
  @ObservationIgnored @DynamicInjected(\.queue) private var queue
  @ObservationIgnored @DynamicInjected(\.refreshManager) private var refreshManager
  @ObservationIgnored @DynamicInjected(\.repo) private var repo
  private var playManager: PlayManager { get async { await Container.shared.playManager() } }

  private let log = Log(LogContext.Podcasts.detail)

  // MARK: - State Management

  var unplayedOnly: Bool = false

  var episodeList = SelectableListUseCase<Episode, Episode.ID>(idKeyPath: \.id)
  var podcast: Podcast { podcastSeries.podcast }

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
    episodeList.filterMethod = { [weak self] in
      guard let self else { return true }
      return !unplayedOnly || !$0.completed
    }
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
      log.report(error)
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

  // MARK: - Public Functions

  func refreshSeries() async throws(RefreshError) {
    try await refreshManager.refreshSeries(podcastSeries: podcastSeries)
  }

  func subscribe() {
    Task { [weak self] in
      guard let self else { return }
      try await repo.markSubscribed(podcast.id)
      navigation.showPodcast(.subscribed, podcastSeries)
    }
  }
}
