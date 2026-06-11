// Copyright Justin Bishop, 2026

import Foundation

// SmartListSortMethod is defined in the data layer; its UI affordance and the
// View-layer SortingMethod conformance live here so Database/ carries no UI
// dependency. Only View code reads appIcon.
extension SmartListSortMethod: SortingMethod {
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
}
