// Copyright Justin Bishop, 2026

import FactoryKit
import Foundation
import GRDB

// Two-layer episode filter: a base predicate (sort/recommendation qualifier)
// ANDed with the debounced text query. Saved podcasts match via FTS (so
// descriptions hit), unsaved previews via in-memory searchableString;
// `allEntries` stays the full podcast, only `filteredEntries` narrows.
@MainActor final class EpisodeListFilter {
  @ObservationIgnored @DynamicInjected(\.observatory) private var observatory
  private static let log = Log.as(LogSubsystem.PodcastsView.detail)

  private let episodeList: PowerList<ListedEpisode>

  init(episodeList: PowerList<ListedEpisode>) {
    self.episodeList = episodeList
  }

  private var filterText = ""
  private var podcastID: Podcast.ID?
  private var baseFilter: (@Sendable (ListedEpisode) -> Bool)?
  private var searchFilter: (@Sendable (ListedEpisode) -> Bool)?
  private var observationTask: Task<Void, Never>?

  func apply(text: String) {
    filterText = text
    restart()
  }

  func setBaseFilter(_ base: (@Sendable (ListedEpisode) -> Bool)?) {
    baseFilter = base
    updateEpisodeFilter()
  }

  // A saved↔unsaved transition swaps the matching strategy, so the active query
  // is recomputed against the new podcast. Same-podcast updates leave the query
  // unchanged — the live observation already tracks the DB — so they must not
  // tear it down and restart it.
  func refresh(podcastID: Podcast.ID?) {
    guard self.podcastID != podcastID else { return }
    self.podcastID = podcastID
    guard !filterText.isEmpty else { return }
    restart()
  }

  func cancel() {
    observationTask?.cancel()
    observationTask = nil
  }

  private func updateEpisodeFilter() {
    switch (baseFilter, searchFilter) {
    case (nil, nil):
      episodeList.filterMethod = nil
    case (let base?, nil):
      episodeList.filterMethod = base
    case (nil, let search?):
      episodeList.filterMethod = search
    case (let base?, let search?):
      episodeList.filterMethod = { base($0) && search($0) }
    }
  }

  private func restart() {
    observationTask?.cancel()
    observationTask = nil

    let text = filterText
    guard !text.isEmpty else {
      searchFilter = nil
      updateEpisodeFilter()
      return
    }

    guard let podcastID else {
      let terms = text.lowercased().split(separator: /\s+/).map(String.init)
      searchFilter = { episode in
        let searchable = episode.searchableString.lowercased()
        return terms.allSatisfy { searchable.contains($0) }
      }
      updateEpisodeFilter()
      return
    }

    let filter = Episode.Columns.podcastId == podcastID && Episode.matchesText(allWordsIn: text)
    observationTask = Task { [weak self] in
      guard let self else { return }
      do {
        for try await matchedIDs in observatory.episodeIDs(filter: filter) {
          try Task.checkCancellation()
          let ids = Set(matchedIDs)
          searchFilter = { episode in
            guard let episodeID = episode.episodeID else { return false }
            return ids.contains(episodeID)
          }
          updateEpisodeFilter()
        }
      } catch is CancellationError {
      } catch {
        Self.log.caughtError(
          "EpisodeListFilter: text filter failed for podcast \(podcastID)",
          error
        )
      }
    }
  }
}
