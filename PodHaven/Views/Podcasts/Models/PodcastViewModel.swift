// Copyright Justin Bishop, 2025

import Factory
import Foundation
import GRDB
import IdentifiedCollections
import SwiftUI

@Observable @MainActor
final class PodcastViewModel: QueueableSelectableList, EpisodeQueueable {
  @ObservationIgnored @LazyInjected(\.alert) private var alert
  @ObservationIgnored @LazyInjected(\.navigation) private var navigation
  @ObservationIgnored @LazyInjected(\.observatory) private var observatory
  @ObservationIgnored @LazyInjected(\.playManager) private var playManager
  @ObservationIgnored @LazyInjected(\.queue) private var queue
  @ObservationIgnored @LazyInjected(\.refreshManager) private var refreshManager
  @ObservationIgnored @LazyInjected(\.repo) private var repo

  // MARK: - EpisodeQueuable protocols

  typealias EpisodeType = Episode

  // MARK: - State Management

  private var _isSelecting = false
  var isSelecting: Bool {
    get { _isSelecting }
    set { withAnimation { _isSelecting = newValue } }
  }
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
        else { throw Err.msg("No return from DB for: \(podcast.toString)") }

        if self.podcastSeries == podcastSeries { continue }
        self.podcastSeries = podcastSeries
      }
    } catch {
      alert.andReport(error)
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

  func queueEpisodeOnTop(_ episode: Episode) {
    Task { try await queue.unshift(episode.id) }
  }

  func queueEpisodeAtBottom(_ episode: Episode) {
    Task { try await queue.append(episode.id) }
  }

  func playEpisode(_ episode: Episode) {
    Task {
      try await playManager.load(PodcastEpisode(podcast: podcast, episode: episode))
      await playManager.play()
    }
  }

  func addSelectedEpisodesToTopOfQueue() {
    Task { try await queue.unshift(episodeList.selectedEntryIDs) }
  }

  func addSelectedEpisodesToBottomOfQueue() {
    Task { try await queue.append(episodeList.selectedEntryIDs) }
  }

  func replaceQueue() {
    Task { try await queue.replace(episodeList.selectedEntryIDs) }
  }

  func replaceQueueAndPlay() {
    Task {
      if let firstEpisode = episodeList.selectedEntries.first {
        try await playManager.load(PodcastEpisode(podcast: podcast, episode: firstEpisode))
        await playManager.play()
        let allExceptFirstEpisode = episodeList.selectedEntries.dropFirst()
        try await queue.replace(allExceptFirstEpisode.map(\.id))
      }
    }
  }
}
