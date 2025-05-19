// Copyright Justin Bishop, 2025

import Foundation

enum LogSubsystem {
  enum Search: String, LogCategorizable {
    case main

    var subsystem: String { "search" }

    var level: LogLevel {
      switch self {
      case .main: return .debug
      }
    }
  }

  enum Database: String, LogCategorizable {
    case appDB

    var subsystem: String { "database" }

    var level: LogLevel {
      switch self {
      case .appDB: return .info
      }
    }
  }

  enum Podcasts: String, LogCategorizable {
    case detail

    var subsystem: String { "podcasts" }

    var level: LogLevel {
      switch self {
      case .detail: return .debug
      }
    }
  }
}
