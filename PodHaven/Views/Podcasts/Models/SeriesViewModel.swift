// Copyright Justin Bishop, 2025

import Factory
import Foundation
import GRDB
import IdentifiedCollections
import SwiftUI

@Observable @MainActor final class SeriesViewModel {
  @ObservationIgnored @LazyInjected(\.alert) private var alert
  @ObservationIgnored @LazyInjected(\.repo) private var repo
  @ObservationIgnored @LazyInjected(\.queue) private var queue
  @ObservationIgnored @LazyInjected(\.refreshManager) private var refreshManager
  @ObservationIgnored @LazyInjected(\.playManager) private var playManager

  // MARK: - State Management

  private var _isSelecting = false
  var isSelecting: Bool {
    get { _isSelecting }
    set { withAnimation { _isSelecting = newValue } }
  }

  var episodeList = EpisodeListUseCase<Episode, GUID>(idKeyPath: \.guid)
  var podcast: Podcast { podcastSeries.podcast }

  private var _podcastSeries: PodcastSeries
  private var podcastSeries: PodcastSeries {
    get { _podcastSeries }
    set {
      _podcastSeries = newValue
      episodeList.allEpisodes = newValue.episodes
    }
  }

  // MARK: - Initialization

  init(podcast: Podcast) {
    self._podcastSeries = PodcastSeries(podcast: podcast)
  }

  func execute() async {
    do {
      try await refreshIfStale()
      try await observePodcast()
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
    Task { try await queue.unshift(episodeList.selectedEpisodeIDs) }
  }

  func addSelectedEpisodesToBottomOfQueue() {
    Task { try await queue.append(episodeList.selectedEpisodeIDs) }
  }

  func replaceQueue() {
    Task { try await queue.replace(episodeList.selectedEpisodeIDs) }
  }

  func replaceQueueAndPlay() {
    Task {
      if let firstEpisode = episodeList.selectedEpisodes.first {
        try await playManager.load(PodcastEpisode(podcast: podcast, episode: firstEpisode))
        await playManager.play()
        let allExceptFirst = episodeList.selectedEpisodes.dropFirst()
        try await queue.replace(allExceptFirst.map(\.id))
      }
    }
  }

  // MARK: - Private Helpers

  private func refreshIfStale() async throws {
    if podcastSeries.podcast.lastUpdate < Date.minutesAgo(15),
      let podcastSeries = try await repo.podcastSeries(podcastSeries.id)
    {
      self.podcastSeries = podcastSeries
      try await refreshSeries()
    }
  }

  private func observePodcast() async throws {
    let observer =
      ValueObservation
      .tracking(
        Podcast
          .filter(id: podcast.id)
          .including(all: Podcast.episodes)
          .asRequest(of: PodcastSeries.self)
          .fetchOne
      )
      .removeDuplicates()

    for try await podcastSeries in observer.values(in: repo.db) {
      guard let podcastSeries = podcastSeries
      else { throw Err.msg("No return from DB for: \(podcast.toString)") }

      if self.podcastSeries == podcastSeries { continue }
      self.podcastSeries = podcastSeries
    }
  }
}
