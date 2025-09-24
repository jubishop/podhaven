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
    case byMostRecentlySubscribed = "Most Recently Subscribed"

    var systemImageName: String {
      switch self {
      case .byTitle:
        return "textformat"
      case .byMostRecentUnfinished:
        return "clock.badge.exclamationmark"
      case .byMostRecentUnstarted:
        return "clock.badge.questionmark"
      case .byMostRecentUnqueued:
        return "clock.badge.xmark"
      case .byMostRecentlySubscribed:
        return "person.crop.circle.badge.plus"
      }
    }

    var menuIconColor: Color {
      switch self {
      case .byTitle:
        return .indigo
      case .byMostRecentUnfinished:
        return .orange
      case .byMostRecentUnstarted:
        return .teal
      case .byMostRecentUnqueued:
        return .pink
      case .byMostRecentlySubscribed:
        return .green
      }
    }

    var sortMethod: (PodcastWithLatestEpisodeDates, PodcastWithLatestEpisodeDates) -> Bool {
      switch self {
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
    self.podcastList = SelectableListUseCase<PodcastWithLatestEpisodeDates, Podcast.ID>(
      idKeyPath: \.id,
      sortMethod: sortMethod.wrappedValue.sortMethod
    )
  }

  func execute() async {
    do {
      for try await podcastsWithLatestEpisodeDates in observatory.podcastsWithLatestEpisodeDates(
        filter
      ) {
        try Task.checkCancellation()
        Self.log.debug("Updating \(podcastsWithLatestEpisodeDates.count) observed episodes")

        self.podcastList.allEntries = IdentifiedArray(
          uniqueElements: podcastsWithLatestEpisodeDates
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
      stalenessThreshold: 1.minutesAgo,
      filter: podcastList.filteredEntryIDs.contains(Podcast.Columns.id)
    )
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

  // MARK: - Single Item Functions

  func queueLatestEpisodeToTop(_ podcastID: Podcast.ID) {
    Task { [weak self] in
      guard let self else { return }
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

  func queueLatestEpisodeToBottom(_ podcastID: Podcast.ID) {
    Task { [weak self] in
      guard let self else { return }
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

  func deletePodcast(_ podcastID: Podcast.ID) {
    Task { [weak self] in
      guard let self else { return }
      try await repo.delete(podcastID)
    }
  }

  func subscribePodcast(_ podcastID: Podcast.ID) {
    Task { [weak self] in
      guard let self else { return }
      try await repo.markSubscribed(podcastID)
    }
  }

  func unsubscribePodcast(_ podcastID: Podcast.ID) {
    Task { [weak self] in
      guard let self else { return }
      try await repo.markUnsubscribed(podcastID)
    }
  }
}
