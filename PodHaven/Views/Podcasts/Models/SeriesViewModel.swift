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

  private var _isSelecting = false
  var isSelecting: Bool {
    get { _isSelecting }
    set {
      withAnimation { _isSelecting = newValue }
    }
  }

  var isSelected = BindableDictionary<Episode, Bool>(defaultValue: false)
  var anySelected: Bool { isSelected.values.contains(true) }

  var selectedEpisodes: EpisodeArray {
    IdentifiedArray(
      uniqueElements: isSelected.keys.filter({ isSelected[$0] && filteredEpisodes.contains($0) }),
      id: \Episode.guid
    )
  }

  var filteredEpisodes: EpisodeArray {
    let searchTerms =
      episodeFilter
      .lowercased()
      .components(separatedBy: CharacterSet.whitespacesAndNewlines)
      .filter { !$0.isEmpty }

    guard !searchTerms.isEmpty else { return podcastSeries.episodes }

    return EpisodeArray(
      podcastSeries.episodes.filter { episode in
        let lowercasedTitle = episode.title.lowercased()
        return searchTerms.allSatisfy { lowercasedTitle.contains($0) }
      }
    )
  }
  var episodeFilter: String = ""

  var podcast: Podcast { podcastSeries.podcast }

  private var podcastSeries: PodcastSeries

  init(podcast: Podcast) {
    self.podcastSeries = PodcastSeries(podcast: podcast)
  }

  func execute() async {
    do {
      try await refreshIfStale()
      try await observePodcast()
    } catch {
      alert.andReport(error)
    }
  }

  func refreshSeries() async throws {
    try await refreshManager.refreshSeries(podcastSeries: podcastSeries)
  }

  func subscribe() {
    Task {
      try await repo.markSubscribed(podcast.id)
    }
  }

  func addSelectedEpisodesToTopOfQueue() {
    Task {
      try await queue.unshift(selectedEpisodes.map(\.id))
    }
  }

  func addSelectedEpisodesToBottomOfQueue() {
    Task {
      try await queue.append(selectedEpisodes.map(\.id))
    }
  }

  func replaceQueue() {
    Task {
      try await queue.replace(selectedEpisodes.map(\.id))
    }
  }

  func replaceQueueAndPlay() {
    Task {
      if let firstEpisode = selectedEpisodes.first {
        try await playManager.load(PodcastEpisode(podcast: podcast, episode: firstEpisode))
        await playManager.play()
        let allExceptFirst = selectedEpisodes.dropFirst()
        try await queue.replace(allExceptFirst.map(\.id))
      }
    }
  }

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
