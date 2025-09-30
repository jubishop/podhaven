// Copyright Justin Bishop, 2025

import Foundation
import Logging

enum LogSubsystem {
  enum Cache: String, LogCategorizable {
    case backgroundDelegate
    case manager
    case purger
    case state

    var level: Logger.Level {
      return .trace
    }
  }

  enum Database: String, LogCategorizable {
    case appDB
    case episode
    case observatory
    case repo
    case queue
  }

  enum EpisodesView: String, LogCategorizable {
    case detail
    case standard
  }

  enum Feed: String, LogCategorizable {
    case feedManager
    case podcast
    case refreshScheduler
    case refreshManager
  }

  enum Play: String, LogCategorizable {
    case audioSession
    case avPlayer
    case commandCenter
    case manager
    case nowPlayingInfo
    case state
  }

  enum PlayBar: String, LogCategorizable {
    case main
  }

  enum PodcastsView: String, LogCategorizable {
    case detail
    case podcastGrid
    case standard
  }

  enum SearchView: String, LogCategorizable {
    case main
    case trending
    case podcast
    case episode
    case manual
  }

  enum SettingsView: String, LogCategorizable {
    case opml
  }

  enum ShareService: String, LogCategorizable {
    case main
  }

  enum UpNextView: String, LogCategorizable {
    case main
  }

  enum ViewProtocols: String, LogCategorizable {
    case podcast
    case episodeList
  }
}
