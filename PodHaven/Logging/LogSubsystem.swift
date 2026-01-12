// Copyright Justin Bishop, 2025

import Foundation
import Logging

enum LogSubsystem {
  enum Cache: String, LogCategorizable {
    case backgroundDelegate
    case manager
    case purger
    case state
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
    case opml
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
    case manual
  }

  enum SettingsView: String, LogCategorizable {
    case main
    case opml
  }

  enum ShareService: String, LogCategorizable {
    case main
  }

  enum State: String, LogCategorizable {
    case manager
  }

  enum UpNextView: String, LogCategorizable {
    case main
  }

  enum ViewProtocols: String, LogCategorizable {
    case episodeList
    case podcastList
    case managingEpisode
    case managingPodcast
  }
}
