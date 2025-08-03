// Copyright Justin Bishop, 2025

import Foundation
import Logging

enum LogSubsystem {
  enum Cache: String, LogCategorizable {
    case cacheManager
  }

  enum Database: String, LogCategorizable {
    case appDB
    case observatory
    case repo
    case queue

    var level: Logger.Level { .debug }
  }

  enum EpisodesView: String, LogCategorizable {
    case detail
    case standard
  }

  enum Feed: String, LogCategorizable {
    case feedManager
    case podcast
    case refreshManager
  }

  enum Play: String, LogCategorizable {
    case commandCenter
    case manager
    case avPlayer
    case nowPlayingInfo

    var level: Logger.Level { .debug }
  }

  enum PodcastsView: String, LogCategorizable {
    case detail
    case standard
  }

  enum SearchView: String, LogCategorizable {
    case main
    case episodeDetail
    case podcastDetail
  }

  enum SettingsView: String, LogCategorizable {
    case opml
  }

  enum ShareService: String, LogCategorizable {
    case main
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
