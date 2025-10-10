// Copyright Justin Bishop, 2025

import SwiftUI

// MARK: - SystemImageName

private struct SystemImageName: RawRepresentable, Equatable, Hashable, Sendable {
  let rawValue: String

  fileprivate init(rawValue: String) {
    self.rawValue = rawValue
  }

  private init(_ rawValue: String) {
    self.rawValue = rawValue
  }

  // App Navigation
  static let episodesList = SystemImageName("list.bullet")
  static let expandDown = SystemImageName("chevron.down")
  static let expandUp = SystemImageName("chevron.up")
  static let moreActions = SystemImageName("ellipsis.circle")
  static let podcastsList = SystemImageName("dot.radiowaves.left.and.right")
  static let search = SystemImageName("magnifyingglass")
  static let settings = SystemImageName("gear")
  static let showPodcast = SystemImageName("antenna.radiowaves.left.and.right")

  // Actions
  static let clearSearch = SystemImageName("xmark")
  static let delete = SystemImageName("trash")
  static let failed = SystemImageName("x.circle")
  static let removeFromQueue = SystemImageName("minus.circle.fill")
  static let subscribe = SystemImageName("plus.circle")
  static let unsubscribe = SystemImageName("minus.circle")
  static let replaceQueue = SystemImageName("arrow.triangle.2.circlepath")

  // Documents & Data
  static let document = SystemImageName("doc.text")
  static let edit = SystemImageName("pencil.circle")
  static let selectAll = SystemImageName("checklist")

  // Episode Status
  static let downloadEpisode = SystemImageName("arrow.down.circle")
  static let episodeCached = SystemImageName("arrow.down.circle.fill")
  static let episodeDownloadCancel = SystemImageName("stop.circle")
  static let episodeUncached = SystemImageName("tray.and.arrow.up")
  static let episodeFinished = SystemImageName("checkmark.circle.fill")
  static let episodeOnDeck = SystemImageName("play.circle")
  static let selectionEmpty = SystemImageName("circle")
  static let selectionFilled = SystemImageName("record.circle")

  // External Links
  static let externalLink = SystemImageName("arrow.up.right")
  static let share = SystemImageName("square.and.arrow.up")
  static let website = SystemImageName("link")
  static let manualEntry = SystemImageName("link.badge.plus")

  // Filtering
  static let filter = SystemImageName("line.horizontal.3.decrease.circle")
  static let filterAllEpisodes = SystemImageName("list.bullet")
  static let filterUnstarted = SystemImageName("play.circle")
  static let filterUnfinished = SystemImageName("circle.lefthalf.filled")
  static let filterUnqueued = SystemImageName("text.badge.minus")

  // Information Display
  static let aboutInfo = SystemImageName("questionmark.circle")
  static let audioPlaceholder = SystemImageName("music.note")
  static let calendar = SystemImageName("calendar")
  static let duration = SystemImageName("clock")
  static let error = SystemImageName("exclamationmark.triangle")
  static let noImage = SystemImageName("photo")
  static let noPersonFound = SystemImageName("person.circle.fill.badge.questionmark")
  static let personSearch = SystemImageName("person.circle")
  static let publishDate = SystemImageName("calendar.badge.clock")
  static let showInfo = SystemImageName("info.circle")
  static let trending = SystemImageName("chart.line.uptrend.xyaxis")
  static let trendingTop = SystemImageName("chart.bar.xaxis")
  static let trendingNews = SystemImageName("newspaper")
  static let trendingTrueCrime = SystemImageName("magnifyingglass.circle")
  static let trendingComedy = SystemImageName("theatermasks")
  static let trendingBusiness = SystemImageName("briefcase.fill")
  static let trendingTechnology = SystemImageName("cpu")
  static let trendingSports = SystemImageName("sportscourt")
  static let trendingHealth = SystemImageName("heart.text.square")
  static let trendingScience = SystemImageName("atom")
  static let trendingEducation = SystemImageName("graduationcap.fill")
  static let trendingKids = SystemImageName("figure.2.and.child.holdinghands")
  static let trendingHistory = SystemImageName("building.columns")

  // Playback Controls
  static let loading = SystemImageName("hourglass.circle")
  static let noEpisode = SystemImageName("waveform.slash")
  static let pauseButton = SystemImageName("pause.circle.fill")
  static let play = SystemImageName("play.fill")
  static let playButton = SystemImageName("play.circle.fill")
  static let seekBackward = SystemImageName("gobackward.15")
  static let seekForward = SystemImageName("goforward.30")

  // Podcast Status
  static let subscribed = SystemImageName("checkmark.circle.fill")

  // Queue Management
  static let editFinished = SystemImageName("checkmark.circle")
  static let episodeQueued = SystemImageName("line.3.horizontal")
  static let moveToTop = SystemImageName("arrow.up.to.line")
  static let moveToBottom = SystemImageName("arrow.down.to.line")
  static let queueBottom = SystemImageName("text.line.last.and.arrowtriangle.forward")
  static let queueTop = SystemImageName("text.line.first.and.arrowtriangle.forward")

  // Sorting
  static let sort = SystemImageName("arrow.up.arrow.down.circle")
  static let sortByTitle = SystemImageName("textformat")
  static let sortByMostRecentUnfinished = SystemImageName("clock.badge.exclamationmark")
  static let sortByMostRecentUnstarted = SystemImageName("clock.badge.questionmark")
  static let sortByMostRecentUnqueued = SystemImageName("clock.badge.xmark")
  static let sortByMostRecentlySubscribed = SystemImageName("person.crop.circle.badge.plus")

  // Status Indicators
  static let waiting = SystemImageName("clock.arrow.circlepath")
}

// MARK: - AppIcon

enum AppIcon: CaseIterable {
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
  case subscribed
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
  case trendingTop
  case trendingNews
  case trendingTrueCrime
  case trendingComedy
  case trendingBusiness
  case trendingTechnology
  case trendingSports
  case trendingHealth
  case trendingScience
  case trendingEducation
  case trendingKids
  case trendingHistory
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

  // Filtering
  case filter
  case filterAllEpisodes
  case filterUnstarted
  case filterUnfinished
  case filterUnqueued

  // Sorting
  case sort
  case sortByTitle
  case sortByMostRecentUnfinished
  case sortByMostRecentUnstarted
  case sortByMostRecentUnqueued
  case sortByMostRecentlySubscribed

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
    let darkColor: Color
    let lightColor: Color

    init(
      text: String,
      systemImageName: SystemImageName,
      darkColor: Color = .accentColor,
      lightColor: Color = .accentColor
    ) {
      self.text = text
      self.systemImageName = systemImageName
      self.darkColor = darkColor
      self.lightColor = lightColor
    }

    init(
      text: String,
      systemImageName: SystemImageName,
      color: Color
    ) {
      self.text = text
      self.systemImageName = systemImageName
      self.darkColor = color
      self.lightColor = color
    }
  }

  // MARK: - Data

  private var data: Data {
    switch self {
    // Episode Actions
    case .addToBottom:
      return Data(text: "Add to Bottom", systemImageName: .queueBottom)
    case .addToTop:
      return Data(text: "Add to Top", systemImageName: .queueTop)
    case .addSelectionToBottom:
      return Data(text: "Add to Bottom of Queue", systemImageName: .queueBottom, color: .purple)
    case .addSelectionToTop:
      return Data(text: "Add to Top of Queue", systemImageName: .queueTop, color: .blue)
    case .cacheEpisode:
      return Data(text: "Cache Episode", systemImageName: .episodeCached, color: .blue)
    case .cancelEpisodeDownload:
      return Data(
        text: "Cancel Download",
        systemImageName: .episodeDownloadCancel,
        color: .orange
      )
    case .uncacheEpisode:
      return Data(text: "Remove Download", systemImageName: .episodeUncached, color: .red)
    case .moveToTop:
      return Data(text: "Move to Top", systemImageName: .moveToTop, color: .blue)
    case .moveToBottom:
      return Data(text: "Move to Bottom", systemImageName: .moveToBottom, color: .purple)
    case .markEpisodeFinished:
      return Data(text: "Mark Finished", systemImageName: .episodeFinished, color: .mint)
    case .playEpisode:
      return Data(text: "Play Episode", systemImageName: .play, color: .green)
    case .playNow:
      return Data(text: "Play Now", systemImageName: .play)
    case .playSelection:
      return Data(text: "Play Selected Episodes", systemImageName: .play, color: .green)
    case .queueAtBottom:
      return Data(text: "Queue at Bottom", systemImageName: .queueBottom, color: .purple)
    case .queueAtTop:
      return Data(text: "Queue at Top", systemImageName: .queueTop, color: .orange)
    case .replaceQueue:
      return Data(text: "Replace Queue", systemImageName: .replaceQueue, color: .indigo)
    case .removeFromQueue:
      return Data(text: "Remove from Queue", systemImageName: .removeFromQueue, color: .red)

    // Podcast Actions
    case .delete:
      return Data(text: "Delete", systemImageName: .delete)
    case .showPodcast:
      return Data(text: "Show Podcast", systemImageName: .showPodcast)
    case .subscribe:
      return Data(text: "Subscribe", systemImageName: .subscribe)
    case .subscribed:
      return Data(text: "Subscribed", systemImageName: .subscribed, color: .green)
    case .unsubscribe:
      return Data(text: "Unsubscribe", systemImageName: .unsubscribe)

    // Navigation
    case .episodes:
      return Data(text: "Episodes", systemImageName: .episodesList)
    case .episodesList:
      return Data(text: "Episodes List", systemImageName: .episodesList)
    case .podcasts:
      return Data(text: "Podcasts", systemImageName: .podcastsList)
    case .search:
      return Data(text: "Search", systemImageName: .search, color: .secondary)
    case .searchEpisodes:
      return Data(text: "Search Episodes", systemImageName: .personSearch, color: .green)
    case .searchPodcasts:
      return Data(text: "Search Podcasts", systemImageName: .search, color: .blue)
    case .settings:
      return Data(text: "Settings", systemImageName: .settings)
    case .trending:
      return Data(text: "Trending", systemImageName: .trending, color: .orange)
    case .trendingTop:
      return Data(text: "Top Podcasts", systemImageName: .trendingTop, color: .orange)
    case .trendingNews:
      return Data(text: "News", systemImageName: .trendingNews, color: .blue)
    case .trendingTrueCrime:
      return Data(text: "True Crime", systemImageName: .trendingTrueCrime, color: .purple)
    case .trendingComedy:
      return Data(text: "Comedy", systemImageName: .trendingComedy, color: .yellow)
    case .trendingBusiness:
      return Data(text: "Business", systemImageName: .trendingBusiness, color: .teal)
    case .trendingTechnology:
      return Data(text: "Technology", systemImageName: .trendingTechnology, color: .indigo)
    case .trendingSports:
      return Data(text: "Sports", systemImageName: .trendingSports, color: .green)
    case .trendingHealth:
      return Data(text: "Health", systemImageName: .trendingHealth, color: .pink)
    case .trendingScience:
      return Data(text: "Science", systemImageName: .trendingScience, color: .mint)
    case .trendingEducation:
      return Data(text: "Education", systemImageName: .trendingEducation, color: .cyan)
    case .trendingKids:
      return Data(text: "Kids & Family", systemImageName: .trendingKids, color: .orange)
    case .trendingHistory:
      return Data(text: "History", systemImageName: .trendingHistory, color: .brown)
    case .upNext:
      return Data(text: "Up Next", systemImageName: .queueTop)

    // General Actions
    case .document:
      return Data(text: "Document", systemImageName: .document)
    case .exportOPML:
      return Data(text: "Export OPML", systemImageName: .share)
    case .importOPML:
      return Data(text: "Import OPML", systemImageName: .downloadEpisode)
    case .queueLatestToBottom:
      return Data(text: "Queue Latest To Bottom", systemImageName: .queueBottom)
    case .queueLatestToTop:
      return Data(text: "Queue Latest To Top", systemImageName: .queueTop)
    case .share:
      return Data(text: "Share", systemImageName: .share)
    case .shareDatabase:
      return Data(text: "Share Database", systemImageName: .share)
    case .shareLogs:
      return Data(text: "Share Logs", systemImageName: .share)

    // Information Display
    case .aboutInfo:
      return Data(text: "About", systemImageName: .aboutInfo)
    case .audioPlaceholder:
      return Data(
        text: "Audio",
        systemImageName: .audioPlaceholder,
        darkColor: .white.opacity(0.6),
        lightColor: .primary.opacity(0.6)
      )
    case .calendar:
      return Data(text: "Updated", systemImageName: .calendar)
    case .duration:
      return Data(text: "Duration", systemImageName: .duration, color: .secondary)
    case .error:
      return Data(text: "Error", systemImageName: .error, color: .red)
    case .noImage:
      return Data(
        text: "No Image",
        systemImageName: .noImage,
        darkColor: .white.opacity(0.8),
        lightColor: .primary.opacity(0.8)
      )
    case .noPersonFound:
      return Data(text: "No Person Found", systemImageName: .noPersonFound, color: .secondary)
    case .personSearch:
      return Data(text: "Person Search", systemImageName: .personSearch, color: .secondary)
    case .publishDate:
      return Data(text: "Published", systemImageName: .publishDate, color: .secondary)
    case .showInfo:
      return Data(text: "Show Info", systemImageName: .showInfo)

    // UI Controls & Status
    case .clearSearch:
      return Data(text: "Clear Search", systemImageName: .clearSearch)
    case .downloadEpisode:
      return Data(text: "Download", systemImageName: .downloadEpisode, color: .blue)
    case .edit:
      return Data(text: "Edit", systemImageName: .edit)
    case .editFinished:
      return Data(text: "Done", systemImageName: .editFinished)
    case .episodeCached:
      return Data(text: "Cached", systemImageName: .episodeCached, color: .green)
    case .episodeFinished:
      return Data(text: "Finished", systemImageName: .episodeFinished, color: .blue)
    case .episodeOnDeck:
      return Data(text: "On Deck", systemImageName: .episodeOnDeck)
    case .episodeQueued:
      return Data(text: "Queued", systemImageName: .episodeQueued, color: .orange)
    case .externalLink:
      return Data(text: "External Link", systemImageName: .externalLink)
    case .expandDown:
      return Data(
        text: "Collapse",
        systemImageName: .expandDown,
        darkColor: .white,
        lightColor: .primary
      )
    case .expandUp:
      return Data(
        text: "Expand",
        systemImageName: .expandUp,
        darkColor: .white,
        lightColor: .primary
      )
    case .failed:
      return Data(text: "Failed", systemImageName: .failed, color: .red)
    case .filter:
      return Data(text: "Filter", systemImageName: .filter)
    case .filterAllEpisodes:
      return Data(text: "All Episodes", systemImageName: .filterAllEpisodes)
    case .filterUnstarted:
      return Data(text: "Unstarted", systemImageName: .filterUnstarted, color: .green)
    case .filterUnfinished:
      return Data(text: "Unfinished", systemImageName: .filterUnfinished, color: .orange)
    case .filterUnqueued:
      return Data(text: "Unqueued", systemImageName: .filterUnqueued, color: .purple)

    // Sorting
    case .sort:
      return Data(text: "Sort", systemImageName: .sort)
    case .sortByTitle:
      return Data(text: "Title", systemImageName: .sortByTitle, color: .indigo)
    case .sortByMostRecentUnfinished:
      return Data(
        text: "Most Recent Unfinished",
        systemImageName: .sortByMostRecentUnfinished,
        color: .orange
      )
    case .sortByMostRecentUnstarted:
      return Data(
        text: "Most Recent Unstarted",
        systemImageName: .sortByMostRecentUnstarted,
        color: .teal
      )
    case .sortByMostRecentUnqueued:
      return Data(
        text: "Most Recent Unqueued",
        systemImageName: .sortByMostRecentUnqueued,
        color: .pink
      )
    case .sortByMostRecentlySubscribed:
      return Data(
        text: "Most Recently Subscribed",
        systemImageName: .sortByMostRecentlySubscribed,
        color: .green
      )

    case .loading:
      return Data(
        text: "Loading",
        systemImageName: .loading,
        darkColor: .white,
        lightColor: .primary
      )
    case .moreActions:
      return Data(text: "More Actions", systemImageName: .moreActions)
    case .noEpisodeSelected:
      return Data(
        text: "No episode selected",
        systemImageName: .noEpisode,
        darkColor: .white,
        lightColor: .primary
      )
    case .pauseButton:
      return Data(text: "Pause", systemImageName: .pauseButton, color: .yellow)
    case .playButton:
      return Data(
        text: "Play",
        systemImageName: .playButton,
        darkColor: .white,
        lightColor: .primary
      )
    case .seekBackward:
      return Data(
        text: "Seek Backward",
        systemImageName: .seekBackward,
        darkColor: .white,
        lightColor: .primary
      )
    case .seekForward:
      return Data(
        text: "Seek Forward",
        systemImageName: .seekForward,
        darkColor: .white,
        lightColor: .primary
      )
    case .selectAll:
      return Data(text: "Select All", systemImageName: .selectAll, color: .blue)
    case .unselectAll:
      return Data(text: "Unselect All", systemImageName: .selectionEmpty, color: .gray)
    case .selectionEmpty:
      return Data(text: "Select", systemImageName: .selectionEmpty)
    case .selectionFilled:
      return Data(text: "Selected", systemImageName: .selectionFilled)
    case .waiting:
      return Data(text: "Waiting", systemImageName: .waiting, color: .green)
    case .website:
      return Data(text: "Website", systemImageName: .website)

    // Manual Entry
    case .manualEntry:
      return Data(text: "Add Feed URL", systemImageName: .manualEntry, color: .purple)
    }
  }

  var label: Label<Text, Image> {
    Label(LocalizedStringKey(data.text), systemImage: data.systemImageName.rawValue)
  }

  var coloredLabel: some View {
    AdaptiveColoredLabel(icon: self)
  }

  var image: Image {
    Image(systemName: data.systemImageName.rawValue)
  }

  var coloredImage: some View {
    AdaptiveColoredImage(icon: self)
  }

  var textKey: LocalizedStringKey { LocalizedStringKey(data.text) }
  var text: String { data.text }

  var systemImageName: String {
    data.systemImageName.rawValue
  }

  func color(for colorScheme: ColorScheme) -> Color {
    colorScheme == .dark ? data.darkColor : data.lightColor
  }

  @MainActor
  func labelButton(action: @MainActor @escaping () -> Void) -> some View {
    AdaptiveLabelButton(icon: self, action: action)
  }

  @MainActor
  func imageButton(action: @MainActor @escaping () -> Void) -> some View {
    AdaptiveImageButton(icon: self, action: action)
  }
}

// MARK: - Adaptive Views

private struct AdaptiveColoredImage: View {
  @Environment(\.colorScheme) private var colorScheme

  let icon: AppIcon

  var body: some View {
    icon.image
      .foregroundColor(icon.color(for: colorScheme))
  }
}

private struct AdaptiveColoredLabel: View {
  @Environment(\.colorScheme) private var colorScheme

  let icon: AppIcon

  var body: some View {
    icon.label
      .tint(icon.color(for: colorScheme))
  }
}

private struct AdaptiveLabelButton: View {
  @Environment(\.colorScheme) private var colorScheme

  let icon: AppIcon
  let action: () -> Void

  var body: some View {
    Button(action: action) { icon.label }
      .tint(icon.color(for: colorScheme))
  }
}

private struct AdaptiveImageButton: View {
  @Environment(\.colorScheme) private var colorScheme

  let icon: AppIcon
  let action: () -> Void

  var body: some View {
    Button(action: action) { icon.image }
      .tint(icon.color(for: colorScheme))
  }
}
