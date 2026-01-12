// Copyright Justin Bishop, 2025

import FactoryKit
import SwiftUI

// MARK: - SystemImageName

@MainActor
private struct SystemImageName:
  Equatable,
  Hashable,
  @MainActor RawRepresentable,
  Sendable
{
  let rawValue: String

  fileprivate init(rawValue: String) {
    self.rawValue = rawValue
  }

  private init(_ rawValue: String) {
    self.rawValue = rawValue
  }

  // App Navigation
  static let episodesList = SystemImageName("list.bullet")
  static let expandUp = SystemImageName("chevron.up")
  static let grid = SystemImageName("square.grid.2x2")
  static let list = SystemImageName("list.bullet")
  static let moreActions = SystemImageName("ellipsis.circle")
  static let podcastsList = SystemImageName("dot.radiowaves.left.and.right")
  static let search = SystemImageName("magnifyingglass")
  static let settings = SystemImageName("gear")
  static let showEpisode = SystemImageName("waveform")
  static let showPodcast = SystemImageName("antenna.radiowaves.left.and.right")

  // Actions
  static let clear = SystemImageName("xmark.circle")
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
  static let episodeSavedInCache = SystemImageName("pin.circle.fill")
  static let episodeUnsavedFromCache = SystemImageName("pin.slash")
  static let episodeDownloadCancel = SystemImageName("stop.circle")
  static let episodeUncached = SystemImageName("tray.and.arrow.up")
  static let episodeFinished = SystemImageName("checkmark.circle.fill")
  static let episodePlaying = SystemImageName("play.circle")
  static let episodePaused = SystemImageName("pause.circle")
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
  static let filterUncached = SystemImageName("tray")
  static let filterUnstarted = SystemImageName("play.circle")
  static let filterUnfinished = SystemImageName("circle.lefthalf.filled")
  static let filterUnqueued = SystemImageName("text.badge.minus")

  // Information Display
  static let aboutInfo = SystemImageName("questionmark.circle")
  static let audioPlaceholder = SystemImageName("music.note")
  static let calendar = SystemImageName("calendar")
  static let duration = SystemImageName("clock")
  static let episodeCount = SystemImageName("number")
  static let error = SystemImageName("exclamationmark.triangle")
  static let noImage = SystemImageName("photo")
  static let publishDate = SystemImageName("calendar.badge.clock")
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
  static let trendingArts = SystemImageName("paintpalette.fill")
  static let trendingGovernment = SystemImageName("seal.fill")
  static let trendingLeisure = SystemImageName("figure.walk")
  static let trendingMusic = SystemImageName("music.note")
  static let trendingSocietyCulture = SystemImageName("globe.americas.fill")
  static let trendingTVFilm = SystemImageName("tv.fill")

  // Playback Controls
  static let loading = SystemImageName("hourglass.circle")
  static let noEpisode = SystemImageName("waveform.slash")
  static let pauseButton = SystemImageName("pause.circle.fill")
  static let play = SystemImageName("play.fill")
  static let playButton = SystemImageName("play.circle.fill")
  static let finishEpisode = SystemImageName("forward.end.fill")
  static let undoSeek = SystemImageName("arrow.uturn.backward")

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
  static let sortByServerOrder = SystemImageName("list.number")
  static let sortByTitle = SystemImageName("textformat")
  static let sortByEpisodeCount = SystemImageName("number")
  static let sortByRecentlySubscribed = SystemImageName("person.crop.circle.badge.plus")
  static let sortByOldest = SystemImageName("calendar")
  static let sortByNewest = SystemImageName("calendar.badge.clock")
  static let sortByLongest = SystemImageName("clock.badge.fill")
  static let sortByShortest = SystemImageName("clock")
  static let sortByMostRecentlyQueued = SystemImageName("clock.arrow.2.circlepath")
  static let sortByLeastRecentlyQueued = SystemImageName("clock.badge")
  static let sortByRecentlyFinished = SystemImageName("checkmark.circle.fill")

  // Status Indicators
  static let waiting = SystemImageName("clock.arrow.circlepath")
}

// MARK: - AppIcon

@MainActor enum AppIcon: CaseIterable {
  // Episode Actions
  case addSelectionToBottom
  case addSelectionToTop
  case cacheEpisode
  case saveEpisodeInCache
  case unsaveEpisodeFromCache
  case cancelEpisodeDownload
  case uncacheEpisode
  case moveToTop
  case moveToBottom
  case markEpisodeFinished
  case playNow
  case playSelection
  case queueAtBottom
  case queueAtTop
  case replaceQueue
  case removeFromQueue
  case showEpisode

  // Podcast Actions
  case delete
  case editItems
  case showPodcast
  case subscribe
  case subscribed
  case unsubscribe

  // Navigation
  case episodes
  case grid
  case list
  case podcasts
  case search
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
  case trendingArts
  case trendingGovernment
  case trendingLeisure
  case trendingMusic
  case trendingSocietyCulture
  case trendingTVFilm
  case upNext

  // Manual Entry
  case manualEntry

  // General Actions
  case document
  case exportOPML
  case importOPML
  case shareEpisode
  case sharePodcast
  case shareDatabase
  case shareLogs

  // Information Display
  case aboutInfo
  case audioPlaceholder
  case duration
  case episodeCount
  case error
  case noImage
  case notificationsDisabled
  case notificationsNotDetermined
  case publishDate
  case updated

  // Filtering
  case filter
  case filterAllEpisodes
  case filterUncached
  case filterUnstarted
  case filterUnfinished
  case filterUnqueued

  // Sorting
  case sort
  case sortByServerOrder
  case sortByTitle
  case sortByEpisodeCount
  case sortByRecentlySubscribed
  case sortByOldest
  case sortByNewest
  case sortByLongest
  case sortByShortest
  case sortByMostRecentlyQueued
  case sortByLeastRecentlyQueued
  case sortByRecentlyFinished

  // UI Controls & Status
  case clear
  case clearSearch
  case downloadEpisode
  case edit
  case editFinished
  case episodeCached
  case episodeSavedInCache
  case episodeFinished
  case episodePaused
  case episodePlaying
  case episodeQueued
  case episodeQueuedAtTop
  case externalLink
  case expandUp
  case failed
  case loading
  case moreActions
  case noEpisodeSelected
  case pauseButton
  case playButton
  case seekBackward
  case seekForward
  case finishEpisode
  case undoSeek
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
      darkColor: Color,
      lightColor: Color
    ) {
      self.text = text
      self.systemImageName = systemImageName
      self.darkColor = darkColor
      self.lightColor = lightColor
    }

    init(
      text: String,
      systemImageName: SystemImageName,
      color: Color = .accentColor
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
    case .addSelectionToBottom:
      return Data(text: "Add to Bottom of Queue", systemImageName: .queueBottom, color: .purple)
    case .addSelectionToTop:
      return Data(text: "Add to Top of Queue", systemImageName: .queueTop, color: .blue)
    case .cacheEpisode:
      return Data(text: "Cache Episode", systemImageName: .episodeCached, color: .green)
    case .saveEpisodeInCache:
      return Data(text: "Save in Cache", systemImageName: .episodeSavedInCache, color: .purple)
    case .unsaveEpisodeFromCache:
      return Data(
        text: "Remove from Saved",
        systemImageName: .episodeUnsavedFromCache,
        color: .orange
      )
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
      return Data(text: "Mark Finished", systemImageName: .episodeFinished, color: .blue)
    case .playNow:
      return Data(text: "Play Now", systemImageName: .play, color: .green)
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
    case .showEpisode:
      return Data(text: "Show Episode", systemImageName: .showEpisode, color: .blue)

    // Podcast Actions
    case .delete:
      return Data(text: "Delete", systemImageName: .delete, color: .red)
    case .editItems:
      return Data(text: "Edit", systemImageName: .edit, color: .purple)
    case .showPodcast:
      return Data(text: "Show Podcast", systemImageName: .showPodcast, color: .blue)
    case .subscribe:
      return Data(text: "Subscribe", systemImageName: .subscribe, color: .green)
    case .subscribed:
      return Data(text: "Subscribed", systemImageName: .subscribed, color: .green)
    case .unsubscribe:
      return Data(text: "Unsubscribe", systemImageName: .unsubscribe, color: .orange)

    // Navigation
    case .episodes:
      return Data(text: "Episodes", systemImageName: .episodesList)
    case .grid:
      return Data(text: "Grid View", systemImageName: .grid)
    case .list:
      return Data(text: "List View", systemImageName: .list)
    case .podcasts:
      return Data(text: "Podcasts", systemImageName: .podcastsList)
    case .search:
      return Data(text: "Search", systemImageName: .search, color: .secondary)
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
    case .trendingArts:
      return Data(text: "Arts", systemImageName: .trendingArts, color: .red)
    case .trendingGovernment:
      return Data(text: "Government", systemImageName: .trendingGovernment, color: .blue)
    case .trendingLeisure:
      return Data(text: "Leisure", systemImageName: .trendingLeisure, color: .gray)
    case .trendingMusic:
      return Data(text: "Music", systemImageName: .trendingMusic, color: .pink)
    case .trendingSocietyCulture:
      return Data(
        text: "Society & Culture",
        systemImageName: .trendingSocietyCulture,
        color: .purple
      )
    case .trendingTVFilm:
      return Data(text: "TV & Film", systemImageName: .trendingTVFilm, color: .indigo)
    case .upNext:
      return Data(text: "Up Next", systemImageName: .queueTop)

    // General Actions
    case .document:
      return Data(text: "Document", systemImageName: .document)
    case .exportOPML:
      return Data(text: "Export OPML", systemImageName: .share)
    case .importOPML:
      return Data(text: "Import OPML", systemImageName: .downloadEpisode)
    case .shareEpisode:
      return Data(text: "Share Episode", systemImageName: .share)
    case .sharePodcast:
      return Data(text: "Share Podcast", systemImageName: .share)
    case .shareDatabase:
      return Data(text: "Share Database", systemImageName: .share)
    case .shareLogs:
      return Data(text: "Share Logs", systemImageName: .share)

    // Information Display
    case .aboutInfo:
      return Data(text: "About", systemImageName: .aboutInfo)
    case .audioPlaceholder:
      return Data(text: "Audio", systemImageName: .audioPlaceholder, color: .primary.opacity(0.6))
    case .duration:
      return Data(text: "Duration", systemImageName: .duration, color: .secondary)
    case .episodeCount:
      return Data(text: "Episodes", systemImageName: .episodeCount, color: .secondary)
    case .error:
      return Data(text: "Error", systemImageName: .error, color: .red)
    case .noImage:
      return Data(text: "No Image", systemImageName: .noImage, color: .primary.opacity(0.8))
    case .notificationsDisabled:
      return Data(
        text: "Notifications are disabled. Tap to open Settings.",
        systemImageName: .error,
        darkColor: .orange,
        lightColor: .brown
      )
    case .notificationsNotDetermined:
      return Data(
        text: "Tap to enable notification permissions.",
        systemImageName: .error,
        darkColor: .orange,
        lightColor: .brown
      )
    case .publishDate:
      return Data(text: "Published", systemImageName: .publishDate, color: .secondary)
    case .updated:
      return Data(text: "Updated", systemImageName: .calendar, color: .secondary)

    // UI Controls & Status
    case .clear:
      return Data(text: "Clear", systemImageName: .clear)
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
    case .episodeSavedInCache:
      return Data(text: "Saved in Cache", systemImageName: .episodeSavedInCache, color: .purple)
    case .episodeFinished:
      return Data(text: "Finished", systemImageName: .episodeFinished, color: .blue)
    case .episodePaused:
      return Data(text: "Paused", systemImageName: .episodePaused)
    case .episodePlaying:
      return Data(text: "Playing", systemImageName: .episodePlaying)
    case .episodeQueued:
      return Data(text: "Queued", systemImageName: .episodeQueued, color: .orange)
    case .episodeQueuedAtTop:
      return Data(text: "Queued at Top", systemImageName: .queueTop, color: .orange)
    case .externalLink:
      return Data(text: "External Link", systemImageName: .externalLink)
    case .expandUp:
      return Data(text: "Expand", systemImageName: .expandUp)
    case .failed:
      return Data(text: "Failed", systemImageName: .failed, color: .red)
    case .filter:
      return Data(text: "Filter", systemImageName: .filter)
    case .filterAllEpisodes:
      return Data(text: "All Episodes", systemImageName: .filterAllEpisodes)
    case .filterUncached:
      return Data(text: "Uncached", systemImageName: .filterUncached, color: .blue)
    case .filterUnstarted:
      return Data(text: "Unstarted", systemImageName: .filterUnstarted, color: .green)
    case .filterUnfinished:
      return Data(text: "Unfinished", systemImageName: .filterUnfinished, color: .orange)
    case .filterUnqueued:
      return Data(text: "Unqueued", systemImageName: .filterUnqueued, color: .purple)

    // Sorting
    case .sort:
      return Data(text: "Sort", systemImageName: .sort)
    case .sortByServerOrder:
      return Data(text: "Server Order", systemImageName: .sortByServerOrder, color: .gray)
    case .sortByTitle:
      return Data(text: "Title", systemImageName: .sortByTitle, color: .indigo)
    case .sortByEpisodeCount:
      return Data(
        text: "Episode Count",
        systemImageName: .sortByEpisodeCount,
        color: .teal
      )
    case .sortByRecentlySubscribed:
      return Data(
        text: "Most Recently Subscribed",
        systemImageName: .sortByRecentlySubscribed,
        color: .green
      )
    case .sortByOldest:
      return Data(
        text: "Oldest First",
        systemImageName: .sortByOldest,
        color: .teal
      )
    case .sortByNewest:
      return Data(
        text: "Newest First",
        systemImageName: .sortByNewest,
        color: .indigo
      )
    case .sortByLongest:
      return Data(
        text: "Longest First",
        systemImageName: .sortByLongest,
        color: .purple
      )
    case .sortByShortest:
      return Data(
        text: "Shortest First",
        systemImageName: .sortByShortest,
        color: .mint
      )
    case .sortByMostRecentlyQueued:
      return Data(
        text: "Most Recently Queued",
        systemImageName: .sortByMostRecentlyQueued,
        color: .cyan
      )
    case .sortByLeastRecentlyQueued:
      return Data(
        text: "Least Recently Queued",
        systemImageName: .sortByLeastRecentlyQueued,
        color: .brown
      )
    case .sortByRecentlyFinished:
      return Data(
        text: "Most Recently Finished",
        systemImageName: .sortByRecentlyFinished,
        color: .blue
      )

    case .loading:
      return Data(text: "Loading", systemImageName: .loading)
    case .moreActions:
      return Data(text: "More Actions", systemImageName: .moreActions)
    case .noEpisodeSelected:
      return Data(text: "No episode selected", systemImageName: .noEpisode)
    case .pauseButton:
      return Data(text: "Pause", systemImageName: .pauseButton, color: .yellow)
    case .playButton:
      return Data(text: "Play", systemImageName: .playButton, color: .green)
    case .seekBackward:
      let interval = Int(Container.shared.userSettings().skipBackwardInterval)
      return Data(
        text: "Seek Backward",
        systemImageName: SystemImageName(rawValue: "gobackward.\(interval)")
      )
    case .seekForward:
      let interval = Int(Container.shared.userSettings().skipForwardInterval)
      return Data(
        text: "Seek Forward",
        systemImageName: SystemImageName(rawValue: "goforward.\(interval)")
      )
    case .finishEpisode:
      return Data(text: "Finish Episode", systemImageName: .finishEpisode, color: .blue)
    case .undoSeek:
      return Data(
        text: "Undo Seek",
        systemImageName: .undoSeek,
        darkColor: .orange,
        lightColor: .brown
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
      return Data(text: "Visit Website", systemImageName: .website)

    // Manual Entry
    case .manualEntry:
      return Data(text: "Add Feed URL", systemImageName: .manualEntry, color: .purple)
    }
  }

  var rawLabel: Label<Text, Image> {
    Label(LocalizedStringKey(data.text), systemImage: data.systemImageName.rawValue)
  }

  var rawImage: Image {
    Image(systemName: data.systemImageName.rawValue)
  }

  var image: some View {
    AppIconImage(icon: self)
  }

  var label: some View {
    AppIconLabel(icon: self)
  }

  var textKey: LocalizedStringKey { LocalizedStringKey(data.text) }
  var text: String { data.text }

  var systemImageName: String {
    data.systemImageName.rawValue
  }

  func color(for colorScheme: ColorScheme) -> Color {
    colorScheme == .dark ? data.darkColor : data.lightColor
  }

  func labelButton(action: @MainActor @escaping () -> Void) -> some View {
    AppIconLabelButton(icon: self, action: action)
  }

  func rawLabelButton(action: @MainActor @escaping () -> Void) -> some View {
    Button(action: action) { rawLabel }
  }

  func imageButton(action: @MainActor @escaping () -> Void) -> some View {
    AppIconImageButton(icon: self, action: action)
  }

  func rawImageButton(action: @MainActor @escaping () -> Void) -> some View {
    Button(action: action) { rawImage }
  }
}

// MARK: - Icon Views

private struct AppIconImage: View {
  @Environment(\.colorScheme) private var colorScheme

  let icon: AppIcon

  var body: some View {
    icon.rawImage
      .foregroundStyle(icon.color(for: colorScheme))
  }
}

private struct AppIconLabel: View {
  @Environment(\.colorScheme) private var colorScheme

  let icon: AppIcon

  var body: some View {
    Label {
      Text(icon.textKey)
    } icon: {
      icon.rawImage
        .foregroundStyle(icon.color(for: colorScheme))
    }
  }
}

private struct AppIconLabelButton: View {
  @Environment(\.colorScheme) private var colorScheme

  let icon: AppIcon
  let action: () -> Void

  var body: some View {
    Button(action: action) {
      AppIconLabel(icon: icon)
    }
    .tint(icon.color(for: colorScheme))
  }
}

private struct AppIconImageButton: View {
  @Environment(\.colorScheme) private var colorScheme

  let icon: AppIcon
  let action: () -> Void

  var body: some View {
    Button(action: action) {
      AppIconImage(icon: icon)
    }
    .tint(icon.color(for: colorScheme))
  }
}
