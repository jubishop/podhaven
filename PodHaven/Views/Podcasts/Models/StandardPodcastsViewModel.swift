// Copyright Justin Bishop, 2025

import FactoryKit
import Foundation
import GRDB
import IdentifiedCollections
import SwiftUI

@Observable @MainActor final class StandardPodcastsViewModel {
  @ObservationIgnored @LazyInjected(\.alert) private var alert
  @ObservationIgnored @LazyInjected(\.observatory) private var observatory
  @ObservationIgnored @LazyInjected(\.refreshManager) private var refreshManager
  @ObservationIgnored @LazyInjected(\.repo) private var repo

  // MARK: - State Management

  private var _isSelecting = false
  var isSelecting: Bool {
    get { _isSelecting }
    set { withAnimation { _isSelecting = newValue } }
  }

  let title: String
  let filter: SQLExpression

  var podcastList = SelectableListUseCase<PodcastWithLatestEpisodeDates, Podcast.ID>(
    idKeyPath: \.id,
    sortMethod: sortMethod(for: .byTitle)
  )
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

  var currentSortMethod = SortMethod.byTitle {
    didSet {
      podcastList.sortMethod = Self.sortMethod(for: currentSortMethod)
    }
  }

  // MARK: - Initialization

  init(title: String, filter: SQLExpression = AppDB.NoOp) {
    self.title = title
    self.filter = filter
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
      alert("Couldn't execute StandardPodcastsViewModel")
    }
  }

  // MARK: - Public Functions

  func refreshPodcasts() async throws {
    try await refreshManager.performRefresh(stalenessThreshold: 1.minutesAgo, filter: filter)
  }

  func deleteSelectedPodcasts() {
    Task {
      try await repo.delete(podcastList.selectedEntryIDs)
    }
  }

  func subscribeSelectedPodcasts() {
    Task {
      try await repo.markSubscribed(podcastList.selectedEntryIDs)
    }
  }

  func unsubscribeSelectedPodcasts() {
    Task {
      try await repo.markUnsubscribed(podcastList.selectedEntryIDs)
    }
  }
}
