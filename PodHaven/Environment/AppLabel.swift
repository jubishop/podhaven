// Copyright Justin Bishop, 2025

import SwiftUI

// MARK: - SystemImageName

private enum SystemImageName: String, CaseIterable {
  // App Navigation
  case episodesList = "list.bullet"
  case expandDown = "chevron.down"
  case expandUp = "chevron.up"
  case moreActions = "ellipsis.circle"
  case podcastsList = "dot.radiowaves.left.and.right"
  case search = "magnifyingglass"
  case settings = "gear"
  case showPodcast = "antenna.radiowaves.left.and.right"

  // Actions
  case clearSearch = "xmark.circle.fill"
  case delete = "trash"
  case failed = "x.circle"
  case removeFromQueue = "minus.circle.fill"
  case subscribe = "plus.circle"
  case unsubscribe = "minus.circle"

  // Documents & Data
  case document = "doc.text"
  case edit = "pencil.circle"
  case queueActions = "text.badge.plus"
  case selectAll = "checklist"

  // Episode Status
  case downloadEpisode = "arrow.down.circle"
  case editComplete = "checkmark.circle"
  case episodeCached = "arrow.down.circle.fill"
  case episodeDownloadCancel = "stop.circle"
  case episodeUncached = "tray.and.arrow.up"
  case episodeCompleted = "checkmark.circle.fill"
  case episodeOnDeck = "play.circle"
  case selectionEmpty = "circle"
  case selectionFilled = "record.circle"

  // External Links
  case externalLink = "arrow.up.right"
  case share = "square.and.arrow.up"
  case website = "link"
  case manualEntry = "link.badge.plus"

  // Filtering
  case filter = "line.horizontal.3.decrease.circle"

  // Information Display
  case aboutInfo = "questionmark.circle"
  case audioPlaceholder = "music.note"
  case calendar = "calendar"
  case duration = "clock"
  case error = "exclamationmark.triangle"
  case noImage = "photo"
  case noPersonFound = "person.circle.fill.badge.questionmark"
  case personSearch = "person.circle"
  case publishDate = "calendar.badge.clock"
  case showInfo = "info.circle"
  case trending = "chart.line.uptrend.xyaxis"

  // Playback Controls
  case loading = "hourglass.circle"
  case noEpisode = "waveform.slash"
  case pauseButton = "pause.circle.fill"
  case play = "play.fill"
  case playButton = "play.circle.fill"
  case seekBackward = "gobackward.15"
  case seekForward = "goforward.30"

  // Queue Management
  case episodeQueued = "line.3.horizontal"
  case moveToTop = "arrow.up.to.line"
  case queueBottom = "text.line.last.and.arrowtriangle.forward"
  case queueTop = "text.line.first.and.arrowtriangle.forward"

  // Status Indicators
  case waiting = "clock.arrow.circlepath"
}

// MARK: - AppLabel

enum AppLabel: CaseIterable {
  // Episode Actions
  case addToBottom
  case addToTop
  case cacheEpisode
  case cancelEpisodeDownload
  case uncacheEpisode
  case moveToTop
  case markEpisodeCompleted
  case playEpisode
  case playNow
  case queueAtBottom
  case queueAtTop
  case removeFromQueue

  // Podcast Actions
  case delete
  case showPodcast
  case subscribe
  case unsubscribe

  // Navigation
  case episodes
  case episodesList
  case podcasts
  case search
  case searchEpisodes
  case searchPodcasts
  case settings
  case trending
  case upNext

  // Manual Entry
  case manualEntry

  // General Actions
  case document
  case exportOPML
  case importOPML
  case queueLatestToBottom
  case queueLatestToTop
  case share
  case shareDatabase
  case shareLogs

  // Information Display
  case aboutInfo
  case audioPlaceholder
  case calendar
  case duration
  case error
  case noImage
  case noPersonFound
  case personSearch
  case publishDate
  case showInfo

  // UI Controls & Status
  case clearSearch
  case downloadEpisode
  case edit
  case editComplete
  case episodeCached
  case episodeCompleted
  case episodeOnDeck
  case episodeQueued
  case externalLink
  case expandDown
  case expandUp
  case failed
  case filter
  case loading
  case moreActions
  case noEpisodeSelected
  case pauseButton
  case playButton
  case queueActions
  case seekBackward
  case seekForward
  case selectAll
  case selectionEmpty
  case selectionFilled
  case waiting
  case website

  private var data: (text: String, systemImageName: SystemImageName) {
    switch self {
    // Episode Actions
    case .addToBottom: return (text: "Add to Bottom", systemImageName: .queueBottom)
    case .addToTop: return (text: "Add to Top", systemImageName: .queueTop)
    case .cacheEpisode: return (text: "Cache Episode", systemImageName: .episodeCached)
    case .cancelEpisodeDownload:
      return (text: "Cancel Download", systemImageName: .episodeDownloadCancel)
    case .uncacheEpisode:
      return (text: "Remove Download", systemImageName: .episodeUncached)
    case .moveToTop: return (text: "Move to Top", systemImageName: .moveToTop)
    case .markEpisodeCompleted:
      return (text: "Mark Completed", systemImageName: .episodeCompleted)
    case .playEpisode: return (text: "Play Episode", systemImageName: .play)
    case .playNow: return (text: "Play Now", systemImageName: .play)
    case .queueAtBottom: return (text: "Queue at Bottom", systemImageName: .queueBottom)
    case .queueAtTop: return (text: "Queue at Top", systemImageName: .queueTop)
    case .removeFromQueue:
      return (text: "Remove from Queue", systemImageName: .removeFromQueue)

    // Podcast Actions
    case .delete: return (text: "Delete", systemImageName: .delete)
    case .showPodcast: return (text: "Show Podcast", systemImageName: .showPodcast)
    case .subscribe: return (text: "Subscribe", systemImageName: .subscribe)
    case .unsubscribe: return (text: "Unsubscribe", systemImageName: .unsubscribe)

    // Navigation
    case .episodes: return (text: "Episodes", systemImageName: .episodesList)
    case .episodesList: return (text: "Episodes List", systemImageName: .episodesList)
    case .podcasts: return (text: "Podcasts", systemImageName: .podcastsList)
    case .search: return (text: "Search", systemImageName: .search)
    case .searchEpisodes: return (text: "Search Episodes", systemImageName: .personSearch)
    case .searchPodcasts: return (text: "Search Podcasts", systemImageName: .search)
    case .settings: return (text: "Settings", systemImageName: .settings)
    case .trending: return (text: "Trending", systemImageName: .trending)
    case .upNext: return (text: "Up Next", systemImageName: .queueTop)

    // General Actions
    case .document: return (text: "Document", systemImageName: .document)
    case .exportOPML: return (text: "Export OPML", systemImageName: .share)
    case .importOPML: return (text: "Import OPML", systemImageName: .downloadEpisode)
    case .queueLatestToBottom:
      return (text: "Queue Latest To Bottom", systemImageName: .queueBottom)
    case .queueLatestToTop:
      return (text: "Queue Latest To Top", systemImageName: .queueTop)
    case .share: return (text: "Share", systemImageName: .share)
    case .shareDatabase: return (text: "Share Database", systemImageName: .share)
    case .shareLogs: return (text: "Share Logs", systemImageName: .share)

    // Information Display
    case .aboutInfo: return (text: "About", systemImageName: .aboutInfo)
    case .audioPlaceholder: return (text: "Audio", systemImageName: .audioPlaceholder)
    case .calendar: return (text: "Calendar", systemImageName: .calendar)
    case .duration: return (text: "Duration", systemImageName: .duration)
    case .error: return (text: "Error", systemImageName: .error)
    case .noImage: return (text: "No Image", systemImageName: .noImage)
    case .noPersonFound: return (text: "No Person Found", systemImageName: .noPersonFound)
    case .personSearch: return (text: "Person Search", systemImageName: .personSearch)
    case .publishDate: return (text: "Published", systemImageName: .publishDate)
    case .showInfo: return (text: "Show Info", systemImageName: .showInfo)

    // UI Controls & Status
    case .clearSearch: return (text: "Clear Search", systemImageName: .clearSearch)
    case .downloadEpisode: return (text: "Download", systemImageName: .downloadEpisode)
    case .edit: return (text: "Edit", systemImageName: .edit)
    case .editComplete: return (text: "Done", systemImageName: .editComplete)
    case .episodeCached: return (text: "Cached", systemImageName: .episodeCached)
    case .episodeCompleted: return (text: "Completed", systemImageName: .episodeCompleted)
    case .episodeOnDeck: return (text: "On Deck", systemImageName: .episodeOnDeck)
    case .episodeQueued: return (text: "Queued", systemImageName: .episodeQueued)
    case .externalLink: return (text: "External Link", systemImageName: .externalLink)
    case .expandDown: return (text: "Collapse", systemImageName: .expandDown)
    case .expandUp: return (text: "Expand", systemImageName: .expandUp)
    case .failed: return (text: "Failed", systemImageName: .failed)
    case .filter: return (text: "Filter", systemImageName: .filter)
    case .loading: return (text: "Loading", systemImageName: .loading)
    case .moreActions: return (text: "More Actions", systemImageName: .moreActions)
    case .noEpisodeSelected:
      return (text: "No episode selected", systemImageName: .noEpisode)
    case .pauseButton: return (text: "Pause", systemImageName: .pauseButton)
    case .playButton: return (text: "Play", systemImageName: .playButton)
    case .queueActions: return (text: "Queue Actions", systemImageName: .queueActions)
    case .seekBackward: return (text: "Seek Backward", systemImageName: .seekBackward)
    case .seekForward: return (text: "Seek Forward", systemImageName: .seekForward)
    case .selectAll: return (text: "Select All", systemImageName: .selectAll)
    case .selectionEmpty: return (text: "Select", systemImageName: .selectionEmpty)
    case .selectionFilled: return (text: "Selected", systemImageName: .selectionFilled)
    case .waiting: return (text: "Waiting", systemImageName: .waiting)
    case .website: return (text: "Website", systemImageName: .website)

    // Manual Entry
    case .manualEntry: return (text: "Add Feed URL", systemImageName: .manualEntry)
    }
  }

  var label: Label<Text, Image> {
    Label(data.text, systemImage: data.systemImageName.rawValue)
  }

  var image: Image {
    Image(systemName: data.systemImageName.rawValue)
  }

  var text: String {
    data.text
  }

  var systemImageName: String {
    data.systemImageName.rawValue
  }

}
