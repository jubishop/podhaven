// Copyright Justin Bishop, 2026

import Foundation
import GRDB

// Lifted out of EpisodesListViewModel so the SmartList model layer and the view
// model share one sort type. DatabaseValueConvertible bridges the rawValue into
// the smartList.sortMethod column. The UI affordance (appIcon) and the
// View-layer SortingMethod conformance live in a separate View-layer extension
// so this data-layer type stays free of UI dependencies.
enum SmartListSortMethod: String, Codable, DatabaseValueConvertible, CaseIterable {
  case newestFirst
  case oldestFirst
  case recentlyAdded
  case longest
  case shortest
  case recentlyFinished
  case recentlyQueued
  case recommendationScore

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
      return Episode.Columns.finishDate.desc
    case .recentlyQueued:
      return Episode.Columns.queueDate.desc
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
