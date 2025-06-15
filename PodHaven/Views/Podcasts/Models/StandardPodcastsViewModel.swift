// Copyright Justin Bishop, 2025

import FactoryKit
import Foundation
import GRDB
import IdentifiedCollections
import Logging
import Sharing
import SwiftUI

@Observable @MainActor class StandardPodcastsViewModel {
  @ObservationIgnored @DynamicInjected(\.alert) private var alert
  @ObservationIgnored @DynamicInjected(\.observatory) private var observatory
  @ObservationIgnored @DynamicInjected(\.refreshManager) private var refreshManager
  @ObservationIgnored @DynamicInjected(\.repo) private var repo

  private let log = Log.as(LogSubsystem.PodcastsView.standard)

  // MARK: - State Management

  private var _isSelecting = false
  var isSelecting: Bool {
    get { _isSelecting }
    set { withAnimation { _isSelecting = newValue } }
  }

  let title: String
  let filter: SQLExpression

  var podcastList: SelectableListUseCase<PodcastWithLatestEpisodeDates, Podcast.ID>
  var anySelectedSubscribed: Bool {
    podcastList.selectedEntries.contains { $0.subscribed == true }
  }
  var anySelectedUnsubscribed: Bool {
    podcastList.selectedEntries.contains { $0.subscribed == false }
  }

  enum SortMethod: String, CaseIterable {
    case byTitle = "Title"
    case byMostRecentUnfinished = "Most Recent Unfinished"
    case byMostRecentUnstarted = "Most Recent Unstarted"
    case byMostRecentUnqueued = "Most Recent Unqueued"
  }

  private static func sortMethod(for sortMethod: SortMethod) -> (
    PodcastWithLatestEpisodeDates, PodcastWithLatestEpisodeDates
  ) -> Bool {
    switch sortMethod {
    case .byTitle:
      return { lhs, rhs in lhs.title < rhs.title }
    case .byMostRecentUnfinished:
      return { lhs, rhs in
        let lhsDate = lhs.maxUnfinishedEpisodePubDate ?? Date.distantPast
        let rhsDate = rhs.maxUnfinishedEpisodePubDate ?? Date.distantPast
        return lhsDate > rhsDate
      }
    case .byMostRecentUnstarted:
      return { lhs, rhs in
        let lhsDate = lhs.maxUnstartedEpisodePubDate ?? Date.distantPast
        let rhsDate = rhs.maxUnstartedEpisodePubDate ?? Date.distantPast
        return lhsDate > rhsDate
      }
    case .byMostRecentUnqueued:
      return { lhs, rhs in
        let lhsDate = lhs.maxUnqueuedEpisodePubDate ?? Date.distantPast
        let rhsDate = rhs.maxUnqueuedEpisodePubDate ?? Date.distantPast
        return lhsDate > rhsDate
      }
    }
  }

  @ObservationIgnored @Shared private var storedSortMethod: SortMethod
  private var _currentSortMethod: SortMethod
  var currentSortMethod: SortMethod {
    get { _currentSortMethod }
    set {
      _currentSortMethod = newValue
      $storedSortMethod.withLock { $0 = newValue }
      podcastList.sortMethod = Self.sortMethod(for: newValue)
    }
  }

  // MARK: - Initialization

  init(title: String, filter: SQLExpression = AppDB.NoOp) {
    let sortMethod = Shared(
      wrappedValue: SortMethod.byTitle,
      .appStorage("StandardPodcastsViewModel.sortMethod.\(title)")
    )
    self._storedSortMethod = sortMethod
    self._currentSortMethod = sortMethod.wrappedValue
    self.title = title
    self.filter = filter
    self.podcastList = SelectableListUseCase<PodcastWithLatestEpisodeDates, Podcast.ID>(
      idKeyPath: \.id,
      sortMethod: Self.sortMethod(for: sortMethod.wrappedValue)
    )
  }

  func execute() async {
    do {
      for try await podcastsWithLatestEpisodeDates in observatory.allPodcastsWithLatestEpisodeDates(
        filter
      ) {
        self.podcastList.allEntries = IdentifiedArray(
          uniqueElements: podcastsWithLatestEpisodeDates
        )
      }
    } catch {
      if ErrorKit.baseError(for: error) is CancellationError { return }
      log.error(error)
      alert(ErrorKit.message(for: error))
    }
  }

  // MARK: - Public Functions

  func refreshPodcasts() async throws(RefreshError) {
    try await refreshManager.performRefresh(stalenessThreshold: 1.minutesAgo, filter: filter)
  }

  func deleteSelectedPodcasts() {
    Task { [weak self] in
      guard let self else { return }
      try await repo.delete(podcastList.selectedEntryIDs)
    }
  }

  func subscribeSelectedPodcasts() {
    Task { [weak self] in
      guard let self else { return }
      try await repo.markSubscribed(podcastList.selectedEntryIDs)
    }
  }

  func unsubscribeSelectedPodcasts() {
    Task { [weak self] in
      guard let self else { return }
      try await repo.markUnsubscribed(podcastList.selectedEntryIDs)
    }
  }
}
