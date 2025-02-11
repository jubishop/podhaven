// Copyright Justin Bishop, 2025

import Factory
import Foundation
import GRDB
import IdentifiedCollections
import SwiftUI

@Observable @MainActor final class SeriesViewModel {
  @ObservationIgnored @LazyInjected(\.repo) private var repo
  @ObservationIgnored @LazyInjected(\.queue) private var queue
  @ObservationIgnored @LazyInjected(\.refreshManager) private var refreshManager

  private var _isSelecting = false
  var isSelecting: Bool {
    get { _isSelecting }
    set {
      withAnimation { _isSelecting = newValue }
    }
  }
  var isSelected = BindableDictionary<Episode, Bool>(defaultValue: false)
  var anySelected: Bool { isSelected.values.contains(true) }

  var podcast: Podcast { podcastSeries.podcast }
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

  private var podcastSeries: PodcastSeries

  init(podcast: Podcast) {
    self.podcastSeries = PodcastSeries(podcast: podcast)
  }

  func refreshIfStale() async throws {
    if podcastSeries.podcast.lastUpdate < Date.minutesAgo(15),
      let podcastSeries = try await repo.podcastSeries(podcastSeries.id)
    {
      self.podcastSeries = podcastSeries
      try await refreshSeries()
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
      try await queue.unshift(
        isSelected.keys.filter({ isSelected[$0] && filteredEpisodes.contains($0) }).map(\.id)
      )
      isSelecting = false
    }
  }

  func observePodcast() async throws {
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
