// Copyright Justin Bishop, 2025

import Factory
import Foundation
import GRDB
import IdentifiedCollections
import SwiftUI

@Observable @MainActor
final class SeriesViewModel: QueueableSelectableList, EpisodeQueueable {
  @ObservationIgnored @LazyInjected(\.alert) private var alert
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

  var episodeList = SelectableListUseCase<Episode, GUID>(idKeyPath: \.guid)
  var selectedEpisodeIDs: [Episode.ID] { episodeList.selectedEntries.map { $0.id } }
  var podcast: Podcast { podcastSeries.podcast }

  private var _podcastSeries: PodcastSeries
  private var podcastSeries: PodcastSeries {
    get { _podcastSeries }
    set {
      _podcastSeries = newValue
      episodeList.allEntries = newValue.episodes
    }
  }

  // MARK: - Initialization

  init(podcast: Podcast) {
    self._podcastSeries = PodcastSeries(podcast: podcast)
    episodeList.customFilter = { [unowned self] in !self.unplayedOnly || !$0.completed }
  }

  func execute() async {
    do {
      if Date.minutesAgo(podcastSeries.podcast.lastUpdate) > 15,
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
    Task { try await repo.markSubscribed(podcast.id) }
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
    Task { try await queue.unshift(selectedEpisodeIDs) }
  }

  func addSelectedEpisodesToBottomOfQueue() {
    Task { try await queue.append(selectedEpisodeIDs) }
  }

  func replaceQueue() {
    Task { try await queue.replace(selectedEpisodeIDs) }
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
