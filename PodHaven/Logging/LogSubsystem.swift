// Copyright Justin Bishop, 2025

import Foundation
import Logging

enum LogSubsystem {
  enum Database: String, LogCategorizable {
    case appDB
    case queue

    var level: Logger.Level {
      switch self {
      case .appDB: return .info
      case .queue: return .debug
      }
    }
  }

  enum Play: String, LogCategorizable {
    case manager
    case avPlayer

    var level: Logger.Level {
      switch self {
      case .manager: return .trace
      case .avPlayer: return .trace
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
