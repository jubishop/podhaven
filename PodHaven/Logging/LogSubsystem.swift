// Copyright Justin Bishop, 2025

import Foundation
import Logging

enum LogSubsystem {
  enum Cache: String, LogCategorizable {
    case backgroundDelegate
    case manager
    case purger
  }

  enum Database: String, LogCategorizable {
    case appDB
    case episode
    case observatory
    case podcast
    case repo
    case queue
    case schema
  }

  enum EpisodesView: String, LogCategorizable {
    case detail
    case list
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
    case list
    case main
    case podcastGrid
  }

  enum SearchView: String, LogCategorizable {
    case main
    case manual
  }

  enum SettingsView: String, LogCategorizable {
    case feedback
    case main
    case opml
    case tags
  }

  enum ShareService: String, LogCategorizable {
    case main
  }

  enum State: String, LogCategorizable {
    case manager
    case shared
  }

  enum UpNextView: String, LogCategorizable {
    case main
  }

  enum Widget: String, LogCategorizable {
    case bundle
    case controlCenter
    case lockScreenNowPlaying
    case nowPlaying
    case queue
    case service
    case snapshotReader
    case writer
  }

  enum ViewProtocols: String, LogCategorizable {
    case episodeList
    case podcastList
    case managingEpisode
    case managingPodcast
  }
}
