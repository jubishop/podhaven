// Copyright Justin Bishop, 2025

import FactoryKit
import Foundation
import GRDB
import IdentifiedCollections
import Logging
import Sharing
import SwiftUI

@Observable @MainActor class PodcastsListViewModel: ManagingPodcasts, SelectablePodcastList {
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

  var podcastList: SelectableListUseCase<PodcastWithEpisodeMetadata<Podcast>>

  enum SortMethod: String, CaseIterable, PodcastSortMethod {
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

    var sortMethod:
      (PodcastWithEpisodeMetadata<Podcast>, PodcastWithEpisodeMetadata<Podcast>) -> Bool
    {
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
  var currentSortMethod: SortMethod {
    get { storedSortMethod }
    set {
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
    self.title = title
    self.filter = filter
    self.podcastList = SelectableListUseCase(sortMethod: sortMethod.wrappedValue.sortMethod)
  }

  func execute() async {
    do {
      for try await podcastsWithEpisodeMetadata in observatory.podcastsWithEpisodeMetadata(
        filter
      ) {
        try Task.checkCancellation()
        Self.log.debug("Updating \(podcastsWithEpisodeMetadata.count) observed episodes")

        podcastList.allEntries = IdentifiedArray(uniqueElements: podcastsWithEpisodeMetadata)
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
}
