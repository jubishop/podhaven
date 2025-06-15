// Copyright Justin Bishop, 2025

import Foundation
import Logging

enum LogSubsystem {
  enum Database: String, LogCategorizable {
    case appDB
    case repo
    case queue

    var level: Logger.Level {
      switch self {
      case .appDB: return .info
      case .queue: return .trace
      case .repo: return .debug
      }
    }
  }

  enum Play: String, LogCategorizable {
    case manager
    case avPlayer

    var level: Logger.Level {
      switch self {
      case .manager: return .debug
      case .avPlayer: return .debug
      }
    }
  }

  enum PodcastsView: String, LogCategorizable {
    case detail
    case standard
  }

  enum SearchView: String, LogCategorizable {
    case main
  }
}
