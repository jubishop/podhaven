// Copyright Justin Bishop, 2025

import FactoryKit
import Foundation
import GRDB
import IdentifiedCollections
import Logging
import Sharing
import SwiftUI

@Observable @MainActor class SelectablePodcastsGridViewModel: ManagingPodcasts {
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
    podcastList.selectedEntries.contains(where: \.subscribed)
  }
  var anySelectedUnsubscribed: Bool {
    podcastList.selectedEntries.contains { $0.subscribed == false }
  }
  var anySelectedSaved: Bool {
    podcastList.selectedEntries.contains(where: \.isSaved)
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
        // Get or create all podcasts in parallel
        let podcastIDs = await withTaskGroup(of: Podcast.ID?.self) { group in
          for entry in podcastList.selectedEntries {
            group.addTask {
              do {
                let podcast = try await self.getOrCreatePodcast(entry)
                return podcast.id
              } catch {
                Log.as(LogSubsystem.PodcastsView.standard).error(error)
                return nil
              }
            }
          }

          var podcastIDs: [Podcast.ID] = []
          for await id in group {
            if let id {
              podcastIDs.append(id)
            }
          }
          return podcastIDs
        }

        try await repo.markSubscribed(podcastIDs)
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

}
