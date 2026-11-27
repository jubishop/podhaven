// Copyright Justin Bishop, 2026

import Foundation

extension PodcastDetailViewModel {
  enum SortMethod: SortingMethod {
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

    var sortMethod: (@Sendable (ListedEpisode, ListedEpisode) -> Bool)? {
      switch self {
      case .newestFirst:
        return { $0.pubDate > $1.pubDate }
      case .oldestFirst:
        return { $0.pubDate < $1.pubDate }
      case .recentlyAdded:
        return { lhs, rhs in
          let lhsDate = lhs.creationDate ?? Date.distantFuture
          let rhsDate = rhs.creationDate ?? Date.distantFuture
          return lhsDate > rhsDate
        }
      case .longest:
        return { $0.duration > $1.duration }
      case .shortest:
        return { $0.duration < $1.duration }
      case .recentlyFinished:
        return { lhs, rhs in
          let lhsDate = lhs.finishDate ?? Date.distantPast
          let rhsDate = rhs.finishDate ?? Date.distantPast
          return lhsDate > rhsDate
        }
      case .recentlyQueued:
        return { lhs, rhs in
          let lhsDate = lhs.queueDate ?? Date.distantPast
          let rhsDate = rhs.queueDate ?? Date.distantPast
          return lhsDate > rhsDate
        }
      case .recommendationScore:
        // Scoring is async; the recommendation coordinator installs the real
        // comparator once the recommendation scores land.
        return nil
      }
    }

    var filterMethod: (@Sendable (ListedEpisode) -> Bool)? {
      switch self {
      case .recentlyFinished:
        return { $0.finished }
      case .recentlyQueued:
        return { $0.previouslyQueued }
      default: return nil
      }
    }
  }
}
