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

  private struct Data {
    let text: String
    let systemImageName: SystemImageName
    let iconColor: Color

    init(text: String, systemImageName: SystemImageName, iconColor: Color = .accentColor) {
      self.text = text
      self.systemImageName = systemImageName
      self.iconColor = iconColor
    }
  }

  private var data: Data {
    switch self {
    // Episode Actions
    case .addToBottom:
      return Data(text: "Add to Bottom", systemImageName: .queueBottom)
    case .addToTop:
      return Data(text: "Add to Top", systemImageName: .queueTop)
    case .addSelectionToBottom:
      return Data(
        text: "Add to Bottom of Queue",
        systemImageName: .queueBottom,
        iconColor: .purple
      )
    case .addSelectionToTop:
      return Data(text: "Add to Top of Queue", systemImageName: .queueTop, iconColor: .blue)
    case .cacheEpisode:
      return Data(text: "Cache Episode", systemImageName: .episodeCached, iconColor: .blue)
    case .cancelEpisodeDownload:
      return Data(
        text: "Cancel Download",
        systemImageName: .episodeDownloadCancel,
        iconColor: .orange
      )
    case .uncacheEpisode:
      return Data(
        text: "Remove Download",
        systemImageName: .episodeUncached,
        iconColor: .red
      )
    case .moveToTop:
      return Data(text: "Move to Top", systemImageName: .moveToTop, iconColor: .blue)
    case .moveToBottom:
      return Data(text: "Move to Bottom", systemImageName: .moveToBottom, iconColor: .purple)
    case .markEpisodeFinished:
      return Data(text: "Mark Finished", systemImageName: .episodeFinished, iconColor: .mint)
    case .playEpisode:
      return Data(text: "Play Episode", systemImageName: .play, iconColor: .green)
    case .playNow:
      return Data(text: "Play Now", systemImageName: .play)
    case .playSelection:
      return Data(text: "Play Selected Episodes", systemImageName: .play, iconColor: .green)
    case .queueAtBottom:
      return Data(text: "Queue at Bottom", systemImageName: .queueBottom, iconColor: .purple)
    case .queueAtTop:
      return Data(text: "Queue at Top", systemImageName: .queueTop, iconColor: .blue)
    case .replaceQueue:
      return Data(text: "Replace Queue", systemImageName: .replaceQueue, iconColor: .indigo)
    case .removeFromQueue:
      return Data(
        text: "Remove from Queue",
        systemImageName: .removeFromQueue,
        iconColor: .red
      )

    // Podcast Actions
    case .delete: return Data(text: "Delete", systemImageName: .delete)
    case .showPodcast:
      return Data(text: "Show Podcast", systemImageName: .showPodcast)
    case .subscribe:
      return Data(text: "Subscribe", systemImageName: .subscribe)
    case .unsubscribe:
      return Data(text: "Unsubscribe", systemImageName: .unsubscribe)

    // Navigation
    case .episodes:
      return Data(text: "Episodes", systemImageName: .episodesList)
    case .episodesList:
      return Data(
        text: "Episodes List",
        systemImageName: .episodesList
      )
    case .podcasts:
      return Data(text: "Podcasts", systemImageName: .podcastsList)
    case .search: return Data(text: "Search", systemImageName: .search)
    case .searchEpisodes:
      return Data(
        text: "Search Episodes",
        systemImageName: .personSearch
      )
    case .searchPodcasts:
      return Data(text: "Search Podcasts", systemImageName: .search)
    case .settings:
      return Data(text: "Settings", systemImageName: .settings)
    case .trending:
      return Data(text: "Trending", systemImageName: .trending)
    case .upNext:
      return Data(text: "Up Next", systemImageName: .queueTop)

    // General Actions
    case .document:
      return Data(text: "Document", systemImageName: .document)
    case .exportOPML:
      return Data(text: "Export OPML", systemImageName: .share)
    case .importOPML:
      return Data(
        text: "Import OPML",
        systemImageName: .downloadEpisode
      )
    case .queueLatestToBottom:
      return Data(
        text: "Queue Latest To Bottom",
        systemImageName: .queueBottom
      )
    case .queueLatestToTop:
      return Data(
        text: "Queue Latest To Top",
        systemImageName: .queueTop
      )
    case .share: return Data(text: "Share", systemImageName: .share)
    case .shareDatabase:
      return Data(text: "Share Database", systemImageName: .share)
    case .shareLogs:
      return Data(text: "Share Logs", systemImageName: .share)

    // Information Display
    case .aboutInfo:
      return Data(text: "About", systemImageName: .aboutInfo)
    case .audioPlaceholder:
      return Data(text: "Audio", systemImageName: .audioPlaceholder)
    case .calendar:
      return Data(text: "Updated", systemImageName: .calendar)
    case .duration:
      return Data(text: "Duration", systemImageName: .duration)
    case .error: return Data(text: "Error", systemImageName: .error)
    case .noImage:
      return Data(text: "No Image", systemImageName: .noImage)
    case .noPersonFound:
      return Data(
        text: "No Person Found",
        systemImageName: .noPersonFound
      )
    case .personSearch:
      return Data(
        text: "Person Search",
        systemImageName: .personSearch
      )
    case .publishDate:
      return Data(text: "Published", systemImageName: .publishDate)
    case .showInfo:
      return Data(text: "Show Info", systemImageName: .showInfo)

    // UI Controls & Status
    case .clearSearch:
      return Data(text: "Clear Search", systemImageName: .clearSearch)
    case .downloadEpisode:
      return Data(text: "Download", systemImageName: .downloadEpisode)
    case .edit: return Data(text: "Edit", systemImageName: .edit)
    case .editFinished:
      return Data(text: "Done", systemImageName: .editFinished)
    case .episodeCached:
      return Data(text: "Cached", systemImageName: .episodeCached)
    case .episodeFinished:
      return Data(text: "Finished", systemImageName: .episodeFinished)
    case .episodeOnDeck:
      return Data(text: "On Deck", systemImageName: .episodeOnDeck)
    case .episodeQueued:
      return Data(text: "Queued", systemImageName: .episodeQueued)
    case .externalLink:
      return Data(
        text: "External Link",
        systemImageName: .externalLink
      )
    case .expandDown:
      return Data(text: "Collapse", systemImageName: .expandDown, iconColor: .white)
    case .expandUp: return Data(text: "Expand", systemImageName: .expandUp, iconColor: .white)
    case .failed: return Data(text: "Failed", systemImageName: .failed)
    case .filter: return Data(text: "Filter", systemImageName: .filter)
    case .loading: return Data(text: "Loading", systemImageName: .loading, iconColor: .white)
    case .moreActions:
      return Data(text: "More Actions", systemImageName: .moreActions)
    case .noEpisodeSelected:
      return Data(text: "No episode selected", systemImageName: .noEpisode, iconColor: .white)
    case .pauseButton:
      return Data(text: "Pause", systemImageName: .pauseButton, iconColor: .yellow)
    case .playButton:
      return Data(text: "Play", systemImageName: .playButton, iconColor: .white)
    case .seekBackward:
      return Data(text: "Seek Backward", systemImageName: .seekBackward, iconColor: .white)
    case .seekForward:
      return Data(text: "Seek Forward", systemImageName: .seekForward, iconColor: .white)
    case .selectAll:
      return Data(text: "Select All", systemImageName: .selectAll, iconColor: .blue)
    case .unselectAll:
      return Data(text: "Unselect All", systemImageName: .selectionEmpty, iconColor: .gray)
    case .selectionEmpty:
      return Data(text: "Select", systemImageName: .selectionEmpty)
    case .selectionFilled:
      return Data(text: "Selected", systemImageName: .selectionFilled)
    case .waiting:
      return Data(text: "Waiting", systemImageName: .waiting)
    case .website:
      return Data(text: "Website", systemImageName: .website)

    // Manual Entry
    case .manualEntry:
      return Data(text: "Add Feed URL", systemImageName: .manualEntry)
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
