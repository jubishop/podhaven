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
      case .appDB: return .debug
      case .queue: return .trace
      case .repo: return .debug
      }
    }
  }

  enum EpisodeView: String, LogCategorizable {
    case detail
  }

  enum Feed: String, LogCategorizable {
    case refreshManager
  }

  enum Play: String, LogCategorizable {
    case manager
    case avPlayer
    case nowPlayingInfo

    var level: Logger.Level {
      switch self {
      case .manager: return .debug
      case .avPlayer: return .debug
      case .nowPlayingInfo: return .info
      }
    }
  }

  enum PodcastsView: String, LogCategorizable {
    case detail
    case standard
  }

  enum SearchView: String, LogCategorizable {
    case main
    case episodeDetail
  }

  enum SettingsView: String, LogCategorizable {
    case opml
  }

  enum UpNextView: String, LogCategorizable {
    case main
    case list
  }

  enum ViewProtocols: String, LogCategorizable {
    case podcast
    case episodeList
  }
}
