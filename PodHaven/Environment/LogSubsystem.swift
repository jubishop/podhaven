// Copyright Justin Bishop, 2025

import Foundation

enum LogSubsystem {
  enum Database: String, LogCategorizable {
    case appDB

    var subsystem: String { "database" }

    var level: LogLevel {
      switch self {
      case .appDB: return .info
      }
    }
  }

  enum PodcastsView: String, LogCategorizable {
    case detail
    case standard

    var subsystem: String { "podcasts-view" }

    var level: LogLevel {
      switch self {
      case .detail: return .info
      case .standard: return .info
      }
    }
  }

  enum SearchView: String, LogCategorizable {
    case main

    var subsystem: String { "search-view" }

    var level: LogLevel {
      switch self {
      case .main: return .info
      }
    }
  }
}
