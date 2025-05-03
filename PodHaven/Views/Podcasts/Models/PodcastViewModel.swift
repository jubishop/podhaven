// Copyright Justin Bishop, 2025

import ErrorKit
import Factory
import Foundation
import GRDB
import IdentifiedCollections
import SwiftUI

@Observable @MainActor
final class PodcastViewModel: QueueableSelectableEpisodeList, PodcastQueueableModel {
  @ObservationIgnored @LazyInjected(\.alert) private var alert
  @ObservationIgnored @LazyInjected(\.navigation) private var navigation
  @ObservationIgnored @LazyInjected(\.observatory) private var observatory
  @ObservationIgnored @LazyInjected(\.playManager) private var playManager
  @ObservationIgnored @LazyInjected(\.queue) private var queue
  @ObservationIgnored @LazyInjected(\.refreshManager) private var refreshManager
  @ObservationIgnored @LazyInjected(\.repo) private var repo

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
    episodeList.filterMethod = { [unowned self] in !self.unplayedOnly || !$0.completed }
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
      alert("Couldn't execute PodcastViewModel")
    }
  }

  // MARK: - PodcastQueueableModel

  func getPodcastEpisode(_ episode: Episode) async throws -> PodcastEpisode {
    PodcastEpisode(podcast: podcast, episode: episode)
  }

  func getEpisodeID(_ episode: Episode) async throws -> Episode.ID { episode.id }

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

  var selectedEpisodeIDs: [Episode.ID] {
    get async throws {
      selectedEpisodes.map(\.id)
    }
  }

  // MARK: - Public Functions

  func refreshSeries() async throws {
    try await refreshManager.refreshSeries(podcastSeries: podcastSeries)
  }

  func subscribe() {
    Task {
      try await repo.markSubscribed(podcast.id)
      navigation.showPodcast(.subscribed, podcastSeries)
    }
  }
}
