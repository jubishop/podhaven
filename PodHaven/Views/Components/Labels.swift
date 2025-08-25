// Copyright Justin Bishop, 2025

import SwiftUI

// MARK: - SystemImageName

/// Centralized enum containing all SF Symbol system image names used throughout the app
/// Names reflect functional intent rather than visual appearance
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
  case episodeCompleted = "checkmark.circle.fill"
  case selectionEmpty = "circle"
  case selectionFilled = "record.circle"

  // External Links
  case externalLink = "arrow.up.right"
  case share = "square.and.arrow.up"
  case website = "link"

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
  case moveToTop = "arrow.up.to.line"
  case queueBottom = "text.line.last.and.arrowtriangle.forward"
  case queueTop = "text.line.first.and.arrowtriangle.forward"

  // Status Indicators
  case waiting = "clock.arrow.circlepath"
}

// MARK: - LabelData

/// Data structure for label information
struct LabelData {
  let text: String
  fileprivate let systemImageName: SystemImageName

  var label: Label<Text, Image> {
    Label(text, systemImage: systemImageName.rawValue)
  }

  var image: Image {
    Image(systemName: systemImageName.rawValue)
  }
}

// MARK: - AppLabel

/// Centralized enum for creating Label views with consistent text and system images
/// Names reflect functional intent rather than visual appearance
enum AppLabel: CaseIterable {
  // Episode Actions
  case addToBottom
  case addToTop
  case cacheEpisode
  case moveToTop
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

  /// Label data containing text and system image information
  var data: LabelData {
    switch self {
    // Episode Actions
    case .addToBottom: return LabelData(text: "Add to Bottom", systemImageName: .queueBottom)
    case .addToTop: return LabelData(text: "Add to Top", systemImageName: .queueTop)
    case .cacheEpisode: return LabelData(text: "Cache Episode", systemImageName: .episodeCached)
    case .moveToTop: return LabelData(text: "Move to Top", systemImageName: .moveToTop)
    case .playEpisode: return LabelData(text: "Play Episode", systemImageName: .play)
    case .playNow: return LabelData(text: "Play Now", systemImageName: .play)
    case .queueAtBottom: return LabelData(text: "Queue at Bottom", systemImageName: .queueBottom)
    case .queueAtTop: return LabelData(text: "Queue at Top", systemImageName: .queueTop)
    case .removeFromQueue: return LabelData(text: "Remove from Queue", systemImageName: .delete)

    // Podcast Actions
    case .delete: return LabelData(text: "Delete", systemImageName: .delete)
    case .showPodcast: return LabelData(text: "Show Podcast", systemImageName: .showPodcast)
    case .subscribe: return LabelData(text: "Subscribe", systemImageName: .subscribe)
    case .unsubscribe: return LabelData(text: "Unsubscribe", systemImageName: .unsubscribe)

    // Navigation
    case .episodes: return LabelData(text: "Episodes", systemImageName: .episodesList)
    case .episodesList: return LabelData(text: "Episodes List", systemImageName: .episodesList)
    case .podcasts: return LabelData(text: "Podcasts", systemImageName: .podcastsList)
    case .search: return LabelData(text: "Search", systemImageName: .search)
    case .searchEpisodes: return LabelData(text: "Search Episodes", systemImageName: .personSearch)
    case .searchPodcasts: return LabelData(text: "Search Podcasts", systemImageName: .search)
    case .settings: return LabelData(text: "Settings", systemImageName: .settings)
    case .trending: return LabelData(text: "Trending", systemImageName: .trending)
    case .upNext: return LabelData(text: "Up Next", systemImageName: .queueTop)

    // General Actions
    case .document: return LabelData(text: "Document", systemImageName: .document)
    case .exportOPML: return LabelData(text: "Export OPML", systemImageName: .share)
    case .importOPML: return LabelData(text: "Import OPML", systemImageName: .downloadEpisode)
    case .queueLatestToBottom:
      return LabelData(text: "Queue Latest To Bottom", systemImageName: .queueBottom)
    case .queueLatestToTop:
      return LabelData(text: "Queue Latest To Top", systemImageName: .queueTop)
    case .share: return LabelData(text: "Share", systemImageName: .share)
    case .shareDatabase: return LabelData(text: "Share Database", systemImageName: .share)
    case .shareLogs: return LabelData(text: "Share Logs", systemImageName: .share)

    // Information Display
    case .aboutInfo: return LabelData(text: "About", systemImageName: .aboutInfo)
    case .audioPlaceholder: return LabelData(text: "Audio", systemImageName: .audioPlaceholder)
    case .calendar: return LabelData(text: "Calendar", systemImageName: .calendar)
    case .duration: return LabelData(text: "Duration", systemImageName: .duration)
    case .error: return LabelData(text: "Error", systemImageName: .error)
    case .noImage: return LabelData(text: "No Image", systemImageName: .noImage)
    case .noPersonFound: return LabelData(text: "No Person Found", systemImageName: .noPersonFound)
    case .personSearch: return LabelData(text: "Person Search", systemImageName: .personSearch)
    case .publishDate: return LabelData(text: "Published", systemImageName: .publishDate)
    case .showInfo: return LabelData(text: "Show Info", systemImageName: .showInfo)

    // UI Controls & Status
    case .clearSearch: return LabelData(text: "Clear Search", systemImageName: .clearSearch)
    case .downloadEpisode: return LabelData(text: "Download", systemImageName: .downloadEpisode)
    case .edit: return LabelData(text: "Edit", systemImageName: .edit)
    case .editComplete: return LabelData(text: "Done", systemImageName: .editComplete)
    case .episodeCached: return LabelData(text: "Cached", systemImageName: .episodeCached)
    case .episodeCompleted: return LabelData(text: "Completed", systemImageName: .episodeCompleted)
    case .externalLink: return LabelData(text: "External Link", systemImageName: .externalLink)
    case .expandDown: return LabelData(text: "Collapse", systemImageName: .expandDown)
    case .expandUp: return LabelData(text: "Expand", systemImageName: .expandUp)
    case .failed: return LabelData(text: "Failed", systemImageName: .failed)
    case .filter: return LabelData(text: "Filter", systemImageName: .filter)
    case .loading: return LabelData(text: "Loading", systemImageName: .loading)
    case .moreActions: return LabelData(text: "More Actions", systemImageName: .moreActions)
    case .noEpisodeSelected:
      return LabelData(text: "No episode selected", systemImageName: .noEpisode)
    case .pauseButton: return LabelData(text: "Pause", systemImageName: .pauseButton)
    case .playButton: return LabelData(text: "Play", systemImageName: .playButton)
    case .queueActions: return LabelData(text: "Queue Actions", systemImageName: .queueActions)
    case .seekBackward: return LabelData(text: "Seek Backward", systemImageName: .seekBackward)
    case .seekForward: return LabelData(text: "Seek Forward", systemImageName: .seekForward)
    case .selectAll: return LabelData(text: "Select All", systemImageName: .selectAll)
    case .selectionEmpty: return LabelData(text: "Select", systemImageName: .selectionEmpty)
    case .selectionFilled: return LabelData(text: "Selected", systemImageName: .selectionFilled)
    case .waiting: return LabelData(text: "Waiting", systemImageName: .waiting)
    case .website: return LabelData(text: "Website", systemImageName: .website)
    }
  }

  /// Creates a Label view with the corresponding text and system image
  var label: Label<Text, Image> {
    data.label
  }

  /// The text portion of the label
  var text: String {
    data.text
  }

  /// The system image name for the label
  var systemImageName: String {
    data.systemImageName.rawValue
  }

  /// The image portion of the label
  var image: Image {
    data.image
  }
}
