// Copyright Justin Bishop, 2025

import FactoryKit
import Foundation
import GRDB
import IdentifiedCollections
import Logging
import Sharing
import SwiftUI

@Observable @MainActor
class PodcastsListViewModel:
  DisplayingPodcasts,
  ManagingPodcasts,
  SelectablePodcastList,
  SortablePodcastList
{
  @ObservationIgnored @DynamicInjected(\.alert) private var alert
  @ObservationIgnored @DynamicInjected(\.observatory) private var observatory
  @ObservationIgnored @DynamicInjected(\.refreshManager) private var refreshManager
  @ObservationIgnored @DynamicInjected(\.queue) private var queue
  @ObservationIgnored @DynamicInjected(\.repo) private var repo

  private static let log = Log.as(LogSubsystem.PodcastsView.list)

  // MARK: - SelectablePodcastList & SortablePodcastList

  var podcastList: PowerList<PodcastWithEpisodeMetadata<Podcast>>

  enum SortMethod: String, SortingMethod {
    case byTitle
    case byMostRecentEpisode
    case byEpisodeCount
    case byMostRecentlySubscribed

    var appIcon: AppIcon {
      switch self {
      case .byTitle:
        return .sortByTitle
      case .byMostRecentEpisode:
        return .sortByNewest
      case .byEpisodeCount:
        return .sortByEpisodeCount
      case .byMostRecentlySubscribed:
        return .sortByRecentlySubscribed
      }
    }

    var sortMethod:
      @Sendable (PodcastWithEpisodeMetadata<Podcast>, PodcastWithEpisodeMetadata<Podcast>) -> Bool
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

    var filterMethod: (@Sendable (PodcastWithEpisodeMetadata<Podcast>) -> Bool)? {
      switch self {
      case .byMostRecentEpisode:
        return { $0.mostRecentEpisodeDate != nil }
      case .byMostRecentlySubscribed:
        return { $0.subscriptionDate != nil }
      default: return nil
      }
    }
  }
  let allSortMethods = SortMethod.allCases

  @ObservationIgnored @Shared private var storedSortMethod: SortMethod
  var currentSortMethod: SortMethod {
    get { storedSortMethod }
    set {
      $storedSortMethod.withLock { $0 = newValue }
      podcastList.filterMethod = newValue.filterMethod
      podcastList.sortMethod = newValue.sortMethod
    }
  }

  // MARK: - State Management

  @ObservationIgnored @Shared(.appStorage("PodcastsList-displayMode"))
  var displayMode: PodcastDisplayMode = .grid

  let title: String
  let filter: SQLExpression
  private(set) var isLoading = true

  // MARK: - Initialization

  init(title: String, filter: SQLExpression = AppDB.NoOp) {
    let sortMethod = Shared(
      wrappedValue: SortMethod.byTitle,
      .appStorage("PodcastsList-sortMethod-\(title)")
    )
    self._storedSortMethod = sortMethod

    self.title = title
    self.filter = filter
    self.podcastList = PowerList(
      filterMethod: sortMethod.wrappedValue.filterMethod,
      sortMethod: sortMethod.wrappedValue.sortMethod
    )
  }

  func execute() async {
    defer { isLoading = false }
    do {
      for try await podcastsWithEpisodeMetadata in observatory.podcastsWithEpisodeMetadata(
        filter
      ) {
        try Task.checkCancellation()
        Self.log.debug("Updating \(podcastsWithEpisodeMetadata.count) observed episodes")

        podcastList.allEntries = IdentifiedArray(uniqueElements: podcastsWithEpisodeMetadata)
        isLoading = false
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
