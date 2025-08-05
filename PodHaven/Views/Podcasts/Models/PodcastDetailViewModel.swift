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

  enum FilterMethod: String, CaseIterable {
    case all = "All Episodes"
    case unstarted = "Unstarted"
    case unfinished = "Unfinished"
    case unqueued = "Unqueued"
  }

  private static func filterMethod(for filterMethod: FilterMethod) -> (Episode) -> Bool {
    switch filterMethod {
    case .all:
      return { _ in true }
    case .unstarted:
      return { !$0.started }
    case .unfinished:
      return { !$0.completed }
    case .unqueued:
      return { !$0.queued }
    }
  }

  var currentFilterMethod: FilterMethod = .all {
    didSet {
      episodeList.filterMethod = Self.filterMethod(for: currentFilterMethod)
    }
  }

  var displayAboutSection: Bool = false

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
    episodeList.filterMethod = Self.filterMethod(for: currentFilterMethod)
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
      if ErrorKit.baseError(for: error) is CancellationError { return }
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
}
