// Copyright Justin Bishop, 2025

import FactoryKit
import Foundation
import GRDB
import IdentifiedCollections
import Logging
import SwiftUI

enum PodcastDisplayMode: String, Codable, DefaultsStorable {
  case grid
  case list
}

@Observable @MainActor
class PodcastsListViewModel:
  ManagingPodcasts,
  SelectablePodcastList,
  SortablePodcastList
{
  @ObservationIgnored @DynamicInjected(\.observatory) private var observatory
  @ObservationIgnored @DynamicInjected(\.refreshManager) private var refreshManager
  @ObservationIgnored @DynamicInjected(\.queue) private var queue

  private static let log = Log.as(LogSubsystem.PodcastsView.list)

  // MARK: - SelectablePodcastList & SortablePodcastList

  var podcastList: PowerList<PodcastWithEpisodeMetadata<ListablePodcast>>

  enum SortMethod: String, Codable, DefaultsStorable, SortingMethod {
    case byTitle
    case byMostRecentEpisode
    case byMostRecentlyAdded
    case byEpisodeCount
    case byMostRecentlySubscribed

    var appIcon: AppIcon {
      switch self {
      case .byTitle:
        return .sortByTitle
      case .byMostRecentEpisode:
        return .sortByNewest
      case .byMostRecentlyAdded:
        return .sortByRecentlyAdded
      case .byEpisodeCount:
        return .sortByEpisodeCount
      case .byMostRecentlySubscribed:
        return .sortByRecentlySubscribed
      }
    }

    var sortMethod:
      @Sendable (
        PodcastWithEpisodeMetadata<ListablePodcast>, PodcastWithEpisodeMetadata<ListablePodcast>
      ) -> Bool
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
      case .byMostRecentlyAdded:
        return { lhs, rhs in lhs.creationDate > rhs.creationDate }
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

  @ObservationIgnored @PersistedBroadcast private var persistedSortMethod: SortMethod
  var currentSortMethod: SortMethod {
    get { persistedSortMethod }
    set {
      $persistedSortMethod.new(newValue)
      podcastList.sortMethod = newValue.sortMethod
    }
  }

  // MARK: - State Management

  @ObservationIgnored @PersistedBroadcast("PodcastsList-displayMode")
  var displayMode: PodcastDisplayMode = .grid

  func toggleDisplayMode() {
    displayMode = displayMode == .grid ? .list : .grid
  }

  let title: String
  let filter: PodcastFilter
  let icon: LucideIcon
  private(set) var isLoading = true

  // MARK: - Initialization

  init(title: String, filter: @escaping PodcastFilter = { $0 }, icon: LucideIcon = .podcast) {
    let persistedSortMethod = PersistedBroadcast(
      wrappedValue: SortMethod.byTitle,
      "PodcastsList-sortMethod-\(title)"
    )
    self._persistedSortMethod = persistedSortMethod

    self.title = title
    self.filter = filter
    self.icon = icon
    self.podcastList = PowerList(
      sortMethod: persistedSortMethod.wrappedValue.sortMethod
    )
  }

  func execute() async {
    defer { isLoading = false }
    do {
      let observation: AsyncValueObservation<[PodcastWithEpisodeMetadata<ListablePodcast>]> =
        observatory.listablePodcastsWithEpisodeMetadata(filter)
      for try await podcastsWithEpisodeMetadata in observation {
        try Task.checkCancellation()
        Self.log.debug("Updating \(podcastsWithEpisodeMetadata.count) observed podcasts")

        podcastList.allEntries = IdentifiedArray(uniqueElements: podcastsWithEpisodeMetadata)
        isLoading = false
      }
    } catch {
      Self.log.caughtError("execute: observation failed for podcast list '\(title)'", error)
    }
  }

  // MARK: - ManagingPodcasts

  func getOrCreatePodcast(_ podcast: ListablePodcast) async throws -> Podcast {
    try await podcast.getPodcast()
  }

  // MARK: - Full Grid Functions

  func refreshPodcasts() async throws {
    try await refreshManager.performRefresh(
      stalenessThreshold: .minutes(1),
      filter: podcastList.filteredEntryIDs.contains(Podcast.Columns.feedURL)
    )
  }
}
