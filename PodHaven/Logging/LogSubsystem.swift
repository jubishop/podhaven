// Copyright Justin Bishop, 2025

import Foundation
import Logging

enum LogSubsystem {
  enum Database: String, LogCategorizable {
    case appDB
    case repo
    case queue
  }

  enum EpisodeView: String, LogCategorizable {
    case detail
  }

  enum Feed: String, LogCategorizable {
    case podcast
    case refreshManager
  }

  enum Play: String, LogCategorizable {
    case manager
    case avPlayer
    case nowPlayingInfo
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

  enum UpNextView: String, LogCategorizable {
    case main
    case list
  }

  enum ViewProtocols: String, LogCategorizable {
    case podcast
    case episodeList
  }
}
