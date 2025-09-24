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
  case replaceQueue = "arrow.triangle.2.circlepath"

  // Documents & Data
  case document = "doc.text"
  case edit = "pencil.circle"
  case selectAll = "checklist"

  // Episode Status
  case downloadEpisode = "arrow.down.circle"
  case episodeCached = "arrow.down.circle.fill"
  case episodeDownloadCancel = "stop.circle"
  case episodeUncached = "tray.and.arrow.up"
  case episodeFinished = "checkmark.circle.fill"
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
  case editFinished = "checkmark.circle"
  case episodeQueued = "line.3.horizontal"
  case moveToTop = "arrow.up.to.line"
  case moveToBottom = "arrow.down.to.line"
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
  case addSelectionToBottom
  case addSelectionToTop
  case cacheEpisode
  case cancelEpisodeDownload
  case uncacheEpisode
  case moveToTop
  case moveToBottom
  case markEpisodeFinished
  case playEpisode
  case playNow
  case playSelection
  case queueAtBottom
  case queueAtTop
  case replaceQueue
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
  case editFinished
  case episodeCached
  case episodeFinished
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
  case seekBackward
  case seekForward
  case selectAll
  case unselectAll
  case selectionEmpty
  case selectionFilled
  case waiting
  case website

  private var data: (text: String, systemImageName: SystemImageName, iconColor: Color) {
    switch self {
    // Episode Actions
    case .addToBottom:
      return (text: "Add to Bottom", systemImageName: .queueBottom, iconColor: defaultIconColor)
    case .addToTop:
      return (text: "Add to Top", systemImageName: .queueTop, iconColor: defaultIconColor)
    case .addSelectionToBottom:
      return (
        text: "Add to Bottom of Queue", systemImageName: .queueBottom, iconColor: .purple
      )
    case .addSelectionToTop:
      return (text: "Add to Top of Queue", systemImageName: .queueTop, iconColor: .blue)
    case .cacheEpisode:
      return (text: "Cache Episode", systemImageName: .episodeCached, iconColor: .blue)
    case .cancelEpisodeDownload:
      return (
        text: "Cancel Download", systemImageName: .episodeDownloadCancel,
        iconColor: .orange
      )
    case .uncacheEpisode:
      return (
        text: "Remove Download", systemImageName: .episodeUncached, iconColor: .red
      )
    case .moveToTop:
      return (text: "Move to Top", systemImageName: .moveToTop, iconColor: .blue)
    case .moveToBottom:
      return (text: "Move to Bottom", systemImageName: .moveToBottom, iconColor: .purple)
    case .markEpisodeFinished:
      return (text: "Mark Finished", systemImageName: .episodeFinished, iconColor: .mint)
    case .playEpisode:
      return (text: "Play Episode", systemImageName: .play, iconColor: .green)
    case .playNow: return (text: "Play Now", systemImageName: .play, iconColor: defaultIconColor)
    case .playSelection:
      return (text: "Play Selected Episodes", systemImageName: .play, iconColor: .green)
    case .queueAtBottom:
      return (text: "Queue at Bottom", systemImageName: .queueBottom, iconColor: .purple)
    case .queueAtTop:
      return (text: "Queue at Top", systemImageName: .queueTop, iconColor: .blue)
    case .replaceQueue:
      return (text: "Replace Queue", systemImageName: .replaceQueue, iconColor: .indigo)
    case .removeFromQueue:
      return (
        text: "Remove from Queue", systemImageName: .removeFromQueue, iconColor: .red
      )

    // Podcast Actions
    case .delete: return (text: "Delete", systemImageName: .delete, iconColor: defaultIconColor)
    case .showPodcast:
      return (text: "Show Podcast", systemImageName: .showPodcast, iconColor: defaultIconColor)
    case .subscribe:
      return (text: "Subscribe", systemImageName: .subscribe, iconColor: defaultIconColor)
    case .unsubscribe:
      return (text: "Unsubscribe", systemImageName: .unsubscribe, iconColor: defaultIconColor)

    // Navigation
    case .episodes:
      return (text: "Episodes", systemImageName: .episodesList, iconColor: defaultIconColor)
    case .episodesList:
      return (text: "Episodes List", systemImageName: .episodesList, iconColor: defaultIconColor)
    case .podcasts:
      return (text: "Podcasts", systemImageName: .podcastsList, iconColor: defaultIconColor)
    case .search: return (text: "Search", systemImageName: .search, iconColor: defaultIconColor)
    case .searchEpisodes:
      return (text: "Search Episodes", systemImageName: .personSearch, iconColor: defaultIconColor)
    case .searchPodcasts:
      return (text: "Search Podcasts", systemImageName: .search, iconColor: defaultIconColor)
    case .settings:
      return (text: "Settings", systemImageName: .settings, iconColor: defaultIconColor)
    case .trending:
      return (text: "Trending", systemImageName: .trending, iconColor: defaultIconColor)
    case .upNext: return (text: "Up Next", systemImageName: .queueTop, iconColor: defaultIconColor)

    // General Actions
    case .document:
      return (text: "Document", systemImageName: .document, iconColor: defaultIconColor)
    case .exportOPML:
      return (text: "Export OPML", systemImageName: .share, iconColor: defaultIconColor)
    case .importOPML:
      return (text: "Import OPML", systemImageName: .downloadEpisode, iconColor: defaultIconColor)
    case .queueLatestToBottom:
      return (
        text: "Queue Latest To Bottom", systemImageName: .queueBottom, iconColor: defaultIconColor
      )
    case .queueLatestToTop:
      return (text: "Queue Latest To Top", systemImageName: .queueTop, iconColor: defaultIconColor)
    case .share: return (text: "Share", systemImageName: .share, iconColor: defaultIconColor)
    case .shareDatabase:
      return (text: "Share Database", systemImageName: .share, iconColor: defaultIconColor)
    case .shareLogs:
      return (text: "Share Logs", systemImageName: .share, iconColor: defaultIconColor)

    // Information Display
    case .aboutInfo:
      return (text: "About", systemImageName: .aboutInfo, iconColor: defaultIconColor)
    case .audioPlaceholder:
      return (text: "Audio", systemImageName: .audioPlaceholder, iconColor: defaultIconColor)
    case .calendar:
      return (text: "Updated", systemImageName: .calendar, iconColor: defaultIconColor)
    case .duration:
      return (text: "Duration", systemImageName: .duration, iconColor: defaultIconColor)
    case .error: return (text: "Error", systemImageName: .error, iconColor: defaultIconColor)
    case .noImage: return (text: "No Image", systemImageName: .noImage, iconColor: defaultIconColor)
    case .noPersonFound:
      return (text: "No Person Found", systemImageName: .noPersonFound, iconColor: defaultIconColor)
    case .personSearch:
      return (text: "Person Search", systemImageName: .personSearch, iconColor: defaultIconColor)
    case .publishDate:
      return (text: "Published", systemImageName: .publishDate, iconColor: defaultIconColor)
    case .showInfo:
      return (text: "Show Info", systemImageName: .showInfo, iconColor: defaultIconColor)

    // UI Controls & Status
    case .clearSearch:
      return (text: "Clear Search", systemImageName: .clearSearch, iconColor: defaultIconColor)
    case .downloadEpisode:
      return (text: "Download", systemImageName: .downloadEpisode, iconColor: defaultIconColor)
    case .edit: return (text: "Edit", systemImageName: .edit, iconColor: defaultIconColor)
    case .editFinished:
      return (text: "Done", systemImageName: .editFinished, iconColor: defaultIconColor)
    case .episodeCached:
      return (text: "Cached", systemImageName: .episodeCached, iconColor: defaultIconColor)
    case .episodeFinished:
      return (text: "Finished", systemImageName: .episodeFinished, iconColor: defaultIconColor)
    case .episodeOnDeck:
      return (text: "On Deck", systemImageName: .episodeOnDeck, iconColor: defaultIconColor)
    case .episodeQueued:
      return (text: "Queued", systemImageName: .episodeQueued, iconColor: defaultIconColor)
    case .externalLink:
      return (text: "External Link", systemImageName: .externalLink, iconColor: defaultIconColor)
    case .expandDown:
      return (text: "Collapse", systemImageName: .expandDown, iconColor: .white)
    case .expandUp: return (text: "Expand", systemImageName: .expandUp, iconColor: .white)
    case .failed: return (text: "Failed", systemImageName: .failed, iconColor: defaultIconColor)
    case .filter: return (text: "Filter", systemImageName: .filter, iconColor: defaultIconColor)
    case .loading: return (text: "Loading", systemImageName: .loading, iconColor: .white)
    case .moreActions:
      return (text: "More Actions", systemImageName: .moreActions, iconColor: defaultIconColor)
    case .noEpisodeSelected:
      return (text: "No episode selected", systemImageName: .noEpisode, iconColor: .white)
    case .pauseButton:
      return (text: "Pause", systemImageName: .pauseButton, iconColor: .yellow)
    case .playButton:
      return (text: "Play", systemImageName: .playButton, iconColor: .white)
    case .seekBackward:
      return (text: "Seek Backward", systemImageName: .seekBackward, iconColor: .white)
    case .seekForward:
      return (text: "Seek Forward", systemImageName: .seekForward, iconColor: .white)
    case .selectAll:
      return (text: "Select All", systemImageName: .selectAll, iconColor: .blue)
    case .unselectAll:
      return (text: "Unselect All", systemImageName: .selectionEmpty, iconColor: .gray)
    case .selectionEmpty:
      return (text: "Select", systemImageName: .selectionEmpty, iconColor: defaultIconColor)
    case .selectionFilled:
      return (text: "Selected", systemImageName: .selectionFilled, iconColor: defaultIconColor)
    case .waiting: return (text: "Waiting", systemImageName: .waiting, iconColor: defaultIconColor)
    case .website: return (text: "Website", systemImageName: .website, iconColor: defaultIconColor)

    // Manual Entry
    case .manualEntry:
      return (text: "Add Feed URL", systemImageName: .manualEntry, iconColor: defaultIconColor)
    }
  }

  private var defaultIconColor: Color {
    .accentColor
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

  var iconColor: Color {
    data.iconColor
  }

  func labelButton(action: @escaping () -> Void) -> some View {
    Button(action: action) {
      label
    }
    .tint(iconColor)
  }

  func imageButton(action: @escaping () -> Void) -> some View {
    Button(action: action) {
      image
    }
    .tint(iconColor)
  }
}
