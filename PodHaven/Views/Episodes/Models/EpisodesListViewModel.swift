// Copyright Justin Bishop, 2025

import FactoryKit
import Foundation
import GRDB
import IdentifiedCollections
import Logging
import Sharing
import SwiftUI

@Observable @MainActor
class EpisodesListViewModel:
  ManagingEpisodes,
  SelectableEpisodeList,
  SortableEpisodeList
{
  @ObservationIgnored @DynamicInjected(\.alert) private var alert
  @ObservationIgnored @DynamicInjected(\.observatory) private var observatory
  @ObservationIgnored @DynamicInjected(\.playManager) private var playManager
  @ObservationIgnored @DynamicInjected(\.queue) private var queue
  @ObservationIgnored @DynamicInjected(\.repo) private var repo

  private static let log = Log.as(LogSubsystem.EpisodesView.list)

  // MARK: - SelectableEpisodeList & SortableEpisodeList

  var episodeList = PowerList<PodcastEpisode>()

  enum SortMethod: String, SortingMethod {
    case newestFirst
    case oldestFirst
    case longest
    case shortest
    case recentlyFinished
    case recentlyQueued

    var appIcon: AppIcon {
      switch self {
      case .newestFirst:
        return .sortByNewest
      case .oldestFirst:
        return .sortByOldest
      case .longest:
        return .sortByLongest
      case .shortest:
        return .sortByShortest
      case .recentlyFinished:
        return .sortByRecentlyFinished
      case .recentlyQueued:
        return .sortByMostRecentlyQueued
      }
    }

    var sqlOrdering: SQLOrdering {
      switch self {
      case .newestFirst:
        return Episode.Columns.pubDate.desc
      case .oldestFirst:
        return Episode.Columns.pubDate.asc
      case .longest:
        return Episode.Columns.duration.desc
      case .shortest:
        return Episode.Columns.duration.asc
      case .recentlyFinished:
        return (Episode.Columns.finishDate ?? Date.distantPast).desc
      case .recentlyQueued:
        return (Episode.Columns.queueDate ?? Date.distantPast).desc
      }
    }

    var sqlFilter: SQLExpression {
      switch self {
      case .recentlyFinished:
        return Episode.finished
      case .recentlyQueued:
        return Episode.previouslyQueued
      default: return AppDB.NoOp
      }
    }
  }
  let allSortMethods = SortMethod.allCases

  @ObservationIgnored @Shared private var storedSortMethod: SortMethod
  var currentSortMethod: SortMethod {
    get { storedSortMethod }
    set { $storedSortMethod.withLock { $0 = newValue } }
  }

  // MARK: - Filter Text

  private var textSearchFilter: SQLExpression {
    filterText
      .split(separator: /\s+/)
      .map { word in
        let pattern = "%\(word.lowercased())%"
        return Episode.contains(pattern) || Podcast.contains(pattern)
      }
      .reduce(AppDB.NoOp) { $0 && $1 }
  }

  private var filterText = ""

  @ObservationIgnored lazy var filterDebouncer = StringDebouncer(
    debounceDuration: .milliseconds(400)
  ) { [weak self] filteredText in
    self?.filterText = filteredText
  }

  // MARK: - State Management

  let title: String
  let filter: SQLExpression
  private(set) var isLoading = true

  @ObservationIgnored private var lastObservationKey: String?
  var observationKey: String {
    "\(currentSortMethod.rawValue)-\(filterText)"
  }

  // MARK: - Initialization

  init(title: String, filter: SQLExpression = AppDB.NoOp) {
    let sortMethod = Shared(
      wrappedValue: SortMethod.newestFirst,
      .appStorage("EpisodesList-sortMethod-\(title)")
    )
    self._storedSortMethod = sortMethod
    self.title = title
    self.filter = filter
  }

  // MARK: - Observation

  func startObservation() async {
    let currentKey = observationKey
    let keyChanged = lastObservationKey != nil && lastObservationKey != currentKey
    lastObservationKey = currentKey

    Self.log.debug(
      """
      Executing observation for \(title) with key \(currentKey), changed: \(keyChanged)
      """
    )

    if keyChanged || episodeList.allEntries.isEmpty { isLoading = true }
    defer { isLoading = false }

    do {
      for try await podcastEpisodes in observatory.podcastEpisodes(
        filter: filter && currentSortMethod.sqlFilter && textSearchFilter,
        order: currentSortMethod.sqlOrdering,
        limit: 200
      ) {
        try Task.checkCancellation()
        Self.log.debug("Updating \(podcastEpisodes.count) observed episodes")

        episodeList.allEntries = IdentifiedArray(uniqueElements: podcastEpisodes)
        isLoading = false
      }
    } catch {
      Self.log.error(error)
      guard ErrorKit.isRemarkable(error) else { return }
      alert(ErrorKit.coreMessage(for: error))
    }
  }
}
