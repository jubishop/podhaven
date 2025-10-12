// Copyright Justin Bishop, 2025

import FactoryKit
import Foundation
import GRDB
import IdentifiedCollections
import Logging
import Sharing
import SwiftUI

@Observable @MainActor class SelectablePodcastsGridViewModel {
  @ObservationIgnored @DynamicInjected(\.alert) private var alert
  @ObservationIgnored @DynamicInjected(\.observatory) private var observatory
  @ObservationIgnored @DynamicInjected(\.refreshManager) private var refreshManager
  @ObservationIgnored @DynamicInjected(\.queue) private var queue
  @ObservationIgnored @DynamicInjected(\.repo) private var repo

  private static let log = Log.as(LogSubsystem.PodcastsView.standard)

  // MARK: - State Management

  private var _isSelecting = false
  var isSelecting: Bool {
    get { _isSelecting }
    set { withAnimation { _isSelecting = newValue } }
  }

  let title: String
  let filter: SQLExpression

  var podcastList: SelectableListUseCase<PodcastWithEpisodeMetadata, FeedURL>
  var anySelectedSubscribed: Bool {
    podcastList.selectedEntries.contains { $0.subscribed == true }
  }
  var anySelectedUnsubscribed: Bool {
    podcastList.selectedEntries.contains { $0.subscribed == false }
  }
  var anySelectedSaved: Bool {
    podcastList.selectedEntries.contains { $0.podcastID != nil }
  }

  func isSaved(_ podcastWithMetadata: PodcastWithEpisodeMetadata) -> Bool {
    podcastWithMetadata.podcastID != nil
  }

  enum SortMethod: String, CaseIterable {
    case byTitle
    case byMostRecentEpisode
    case byEpisodeCount
    case byMostRecentlySubscribed

    var appIcon: AppIcon {
      switch self {
      case .byTitle:
        return .sortByTitle
      case .byMostRecentEpisode:
        return .sortByMostRecentEpisode
      case .byEpisodeCount:
        return .sortByEpisodeCount
      case .byMostRecentlySubscribed:
        return .sortByMostRecentlySubscribed
      }
    }

    var sortMethod: (PodcastWithEpisodeMetadata, PodcastWithEpisodeMetadata) -> Bool {
      switch self {
      case .byTitle:
        return { lhs, rhs in lhs.title < rhs.title }
      case .byMostRecentEpisode:
        return { lhs, rhs in
          let lhsDate = lhs.mostRecentEpisodeDate ?? Date.distantPast
          let rhsDate = rhs.mostRecentEpisodeDate ?? Date.distantPast
          return lhsDate > rhsDate
        }
      case .byEpisodeCount:
        return { lhs, rhs in lhs.episodeCount > rhs.episodeCount }
      case .byMostRecentlySubscribed:
        return { lhs, rhs in
          let lhsDate = lhs.subscriptionDate ?? Date.distantPast
          let rhsDate = rhs.subscriptionDate ?? Date.distantPast
          return lhsDate > rhsDate
        }
      }
    }
  }
  let allSortMethods = SortMethod.allCases

  @ObservationIgnored @Shared private var storedSortMethod: SortMethod
  private var _currentSortMethod: SortMethod
  var currentSortMethod: SortMethod {
    get { _currentSortMethod }
    set {
      _currentSortMethod = newValue
      $storedSortMethod.withLock { $0 = newValue }
      podcastList.sortMethod = newValue.sortMethod
    }
  }

  // MARK: - Initialization

  init(title: String, filter: SQLExpression = AppDB.NoOp) {
    let sortMethod = Shared(
      wrappedValue: SortMethod.byTitle,
      .appStorage("SelectablePodcastsGridViewModel-sortMethod-\(title)")
    )
    self._storedSortMethod = sortMethod
    self._currentSortMethod = sortMethod.wrappedValue
    self.title = title
    self.filter = filter
    self.podcastList = SelectableListUseCase<PodcastWithEpisodeMetadata, FeedURL>(
      idKeyPath: \.id,
      sortMethod: sortMethod.wrappedValue.sortMethod
    )
  }

  func execute() async {
    do {
      for try await podcastsWithEpisodeMetadata in observatory.podcastsWithEpisodeMetadata(
        filter
      ) {
        try Task.checkCancellation()
        Self.log.debug("Updating \(podcastsWithEpisodeMetadata.count) observed episodes")

        self.podcastList.allEntries = IdentifiedArray(
          uniqueElements: podcastsWithEpisodeMetadata
        )
      }
    } catch {
      Self.log.error(error)
      guard ErrorKit.isRemarkable(error) else { return }
      alert(ErrorKit.coreMessage(for: error))
    }
  }

  // MARK: - Full Grid Functions

  func refreshPodcasts() async throws(RefreshError) {
    try await refreshManager.performRefresh(
      stalenessThreshold: .minutes(1),
      filter: podcastList.filteredEntryIDs.contains(Podcast.Columns.feedURL)
    )
  }

  func deleteSelectedPodcasts() {
    Task { [weak self] in
      guard let self else { return }
      let podcastIDs = podcastList.selectedEntries.compactMap(\.podcastID)
      try await repo.delete(podcastIDs)
    }
  }

  func subscribeSelectedPodcasts() {
    Task { [weak self] in
      guard let self else { return }
      do {
        // Mark already saved podcasts as subscribed
        try await repo.markSubscribed(podcastList.selectedEntries.compactMap(\.podcastID))

        // For unsaved podcasts, parse feed and insert with subscription in parallel
        let unsavedPodcasts = podcastList.selectedEntries.compactMap {
          $0.displayedPodcast.getUnsavedPodcast()
        }
        guard !unsavedPodcasts.isEmpty else { return }

        await withThrowingTaskGroup(of: Void.self) { group in
          for unsavedPodcast in unsavedPodcasts {
            group.addTask {
              do {
                let podcastFeed = try await PodcastFeed.parse(unsavedPodcast.feedURL)
                var updatedPodcast = try podcastFeed.toUnsavedPodcast()
                updatedPodcast.subscriptionDate = Date()
                try await self.repo.insertSeries(
                  updatedPodcast,
                  unsavedEpisodes: Array(podcastFeed.toEpisodeArray())
                )
              } catch {
                Log.as(LogSubsystem.PodcastsView.standard).error(error)
              }
            }
          }
        }
      } catch {
        Self.log.error(error)
        guard ErrorKit.isRemarkable(error) else { return }
        alert(ErrorKit.coreMessage(for: error))
      }
    }
  }

  func unsubscribeSelectedPodcasts() {
    Task { [weak self] in
      guard let self else { return }
      let podcastIDs = podcastList.selectedEntries.compactMap(\.podcastID)
      try await repo.markUnsubscribed(podcastIDs)
    }
  }

  // MARK: - Single Item Functions

  func queueLatestEpisodeToTop(_ podcastWithMetadata: PodcastWithEpisodeMetadata) {
    Task { [weak self] in
      guard let self else { return }
      guard let podcastID = podcastWithMetadata.podcastID else { return }
      do {
        let latestEpisode = try await repo.latestEpisode(for: podcastID)
        if let latestEpisode = latestEpisode {
          try await queue.unshift(latestEpisode.id)
        }
      } catch {
        Self.log.error(error)
      }
    }
  }

  func queueLatestEpisodeToBottom(_ podcastWithMetadata: PodcastWithEpisodeMetadata) {
    Task { [weak self] in
      guard let self else { return }
      guard let podcastID = podcastWithMetadata.podcastID else { return }
      do {
        let latestEpisode = try await repo.latestEpisode(for: podcastID)
        if let latestEpisode = latestEpisode {
          try await queue.append(latestEpisode.id)
        }
      } catch {
        Self.log.error(error)
      }
    }
  }

  func deletePodcast(_ podcastWithMetadata: PodcastWithEpisodeMetadata) {
    Task { [weak self] in
      guard let self else { return }
      guard let podcastID = podcastWithMetadata.podcastID else { return }
      try await repo.delete(podcastID)
    }
  }

  func subscribePodcast(_ podcastWithMetadata: PodcastWithEpisodeMetadata) {
    Task { [weak self] in
      guard let self else { return }
      do {
        if let podcastID = podcastWithMetadata.podcastID {
          // Already saved, just mark as subscribed
          try await repo.markSubscribed(podcastID)
        } else if var unsavedPodcast = podcastWithMetadata.displayedPodcast.getUnsavedPodcast() {
          // Not saved yet, parse feed and insert
          let podcastFeed = try await PodcastFeed.parse(unsavedPodcast.feedURL)
          unsavedPodcast = try podcastFeed.toUnsavedPodcast()
          unsavedPodcast.subscriptionDate = Date()
          try await repo.insertSeries(
            unsavedPodcast,
            unsavedEpisodes: Array(podcastFeed.toEpisodeArray())
          )
        } else {
          Assert.fatal("Podcast somehow neither saved no unsaved?")
        }
      } catch {
        Self.log.error(error)
        guard ErrorKit.isRemarkable(error) else { return }
        alert(ErrorKit.coreMessage(for: error))
      }
    }
  }

  func unsubscribePodcast(_ podcastWithMetadata: PodcastWithEpisodeMetadata) {
    Task { [weak self] in
      guard let self else { return }
      guard let podcastID = podcastWithMetadata.podcastID else { return }
      try await repo.markUnsubscribed(podcastID)
    }
  }
}
