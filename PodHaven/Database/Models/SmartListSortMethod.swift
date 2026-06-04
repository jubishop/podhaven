// Copyright Justin Bishop, 2026

import Foundation
import GRDB

// Lifted out of EpisodesListViewModel so the SmartList model layer and the view
// model share one sort type. DatabaseValueConvertible bridges the rawValue into
// the smartList.sortMethod column; DefaultsStorable is retained while
// EpisodesListView still persists sort via @PersistedBroadcast.
enum SmartListSortMethod:
  String, Codable, DatabaseValueConvertible, DefaultsStorable, SortingMethod
{
  case newestFirst
  case oldestFirst
  case recentlyAdded
  case longest
  case shortest
  case recentlyFinished
  case recentlyQueued
  case recommendationScore

  var appIcon: AppIcon {
    switch self {
    case .newestFirst:
      return .sortByNewest
    case .oldestFirst:
      return .sortByOldest
    case .recentlyAdded:
      return .sortByRecentlyAdded
    case .longest:
      return .sortByLongest
    case .shortest:
      return .sortByShortest
    case .recentlyFinished:
      return .sortByRecentlyFinished
    case .recentlyQueued:
      return .sortByMostRecentlyQueued
    case .recommendationScore:
      return .sortByRecommendationScore
    }
  }

  var sqlOrdering: SQLOrdering? {
    switch self {
    case .newestFirst:
      return Episode.Columns.pubDate.desc
    case .oldestFirst:
      return Episode.Columns.pubDate.asc
    case .recentlyAdded:
      return Episode.Columns.creationDate.desc
    case .longest:
      return Episode.Columns.duration.desc
    case .shortest:
      return Episode.Columns.duration.asc
    case .recentlyFinished:
      return (Episode.Columns.finishDate ?? Date.distantPast).desc
    case .recentlyQueued:
      return (Episode.Columns.queueDate ?? Date.distantPast).desc
    case .recommendationScore:
      // Sorted in memory from the cached score map.
      return nil
    }
  }

  var sqlFilter: SQLExpression {
    switch self {
    case .recentlyFinished:
      return Episode.finished
    case .recentlyQueued:
      return Episode.previouslyQueued
    default: return AppDB.noOp
    }
  }
}
