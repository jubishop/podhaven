// Copyright Justin Bishop, 2025

import SwiftUI

// MARK: - AppIcon

@MainActor enum AppIcon: Equatable, Hashable, Sendable {
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
  case playFromHere
  case playNow
  case playSelection
  case queueAtBottom
  case queueAtTop
  case replaceQueue
  case removeFromQueue
  case showEpisode

  // Episode Rating Actions
  case loveEpisode
  case likeEpisode
  case dislikeEpisode
  case notInterestedEpisode
  case rateEpisode
  case clearRating
  case embeddingPending

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

  // Smart List Actions
  case addSmartList
  case removeSmartListCondition
  case removeSmartListGroup

  // Tag Actions
  case addTag
  case manageTags
  case removeTag

  // General Actions
  case exportOPML
  case shareEpisode
  case shareEpisodeFromStart
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
  case recommendation
  case recommendationSimilar
  case recommendationFromPodcast
  case recommendationRecent
  case similarityScore
  case tag
  case updated

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
  case sortByRecentlyAdded
  case sortByRecentlyFinished
  case sortByRecommendationScore

  // UI Controls & Status
  case navigateInto
  case clear
  case clearSearch
  case downloadEpisode
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
  case nextChapter
  case previousChapter
  case seekBackward(Int)
  case seekForward(Int)
  case finishEpisode
  case stopAfterEpisode
  case stopAfterEpisodeOn
  case jumpToMaxPosition
  case undoSeekBackward
  case undoSeekForward
  case selectAll
  case unselectAll
  case selectionEmpty
  case selectionFilled
  case waiting
  case website

  // Brand Links
  case discord
  case github

  private enum IconSource {
    case system(SystemImageName)
    case asset(String)
  }

  private struct Data {
    let text: String
    let source: IconSource
    let darkColor: Color
    let lightColor: Color

    init(
      text: String,
      systemImageName: SystemImageName,
      darkColor: Color,
      lightColor: Color
    ) {
      self.text = text
      self.source = .system(systemImageName)
      self.darkColor = darkColor
      self.lightColor = lightColor
    }

    init(
      text: String,
      systemImageName: SystemImageName,
      color: Color = .accentColor
    ) {
      self.text = text
      self.source = .system(systemImageName)
      self.darkColor = color
      self.lightColor = color
    }

    init(
      text: String,
      asset: String,
      color: Color = .accentColor
    ) {
      self.text = text
      self.source = .asset(asset)
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
    case .playFromHere:
      return Data(text: "Play from here", systemImageName: .play, color: .green)
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

    // Episode Rating Actions
    case .loveEpisode:
      return Data(text: "Love", systemImageName: .loveEpisode, color: .pink)
    case .likeEpisode:
      return Data(text: "Like", systemImageName: .likeEpisode, color: .blue)
    case .dislikeEpisode:
      return Data(text: "Dislike", systemImageName: .dislikeEpisode, color: .gray)
    case .notInterestedEpisode:
      return Data(text: "Not Interested", systemImageName: .notInterestedEpisode, color: .brown)
    case .rateEpisode:
      return Data(text: "Rate Episode", systemImageName: .rateEpisode, color: .indigo)
    case .clearRating:
      return Data(text: "Clear Rating", systemImageName: .clear, color: .red)
    case .embeddingPending:
      return Data(
        text: "Awaiting recommendation processing",
        systemImageName: .embeddingPending,
        color: .secondary
      )

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
      return Data(
        text: "Comedy",
        systemImageName: .trendingComedy,
        darkColor: .yellow,
        lightColor: .orange
      )
    case .trendingBusiness:
      return Data(
        text: "Business",
        systemImageName: .trendingBusiness,
        darkColor: .teal,
        lightColor: .blue
      )
    case .trendingTechnology:
      return Data(text: "Technology", systemImageName: .trendingTechnology, color: .indigo)
    case .trendingSports:
      return Data(text: "Sports", systemImageName: .trendingSports, color: .green)
    case .trendingHealth:
      return Data(text: "Health", systemImageName: .trendingHealth, color: .pink)
    case .trendingScience:
      return Data(
        text: "Science",
        systemImageName: .trendingScience,
        darkColor: .mint,
        lightColor: .green
      )
    case .trendingEducation:
      return Data(
        text: "Education",
        systemImageName: .trendingEducation,
        darkColor: .cyan,
        lightColor: .blue
      )
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

    // Smart List Actions
    case .addSmartList:
      return Data(text: "New Smart List", systemImageName: .addSmartList, color: .green)
    case .removeSmartListCondition:
      return Data(text: "Remove Condition", systemImageName: .removeSmartListCondition, color: .red)
    case .removeSmartListGroup:
      return Data(text: "Remove Group", systemImageName: .removeSmartListGroup, color: .red)

    // Tag Actions
    case .addTag:
      return Data(text: "Add Tag", systemImageName: .addTag, color: .green)
    case .manageTags:
      return Data(text: "Manage Tags", systemImageName: .tag)
    case .removeTag:
      return Data(text: "Remove Tag", systemImageName: .removeTag, color: .red)

    // General Actions
    case .exportOPML:
      return Data(text: "Export OPML", systemImageName: .share)
    case .shareEpisode:
      return Data(text: "Share Episode", systemImageName: .share)
    case .shareEpisodeFromStart:
      return Data(text: "Share from Start", systemImageName: .share)
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
    case .recommendation:
      return Data(
        text: "Recommendation",
        systemImageName: .recommendation,
        darkColor: .yellow,
        lightColor: .orange
      )
    case .recommendationSimilar:
      return Data(
        text: "Similar to others",
        systemImageName: .recommendationSimilar,
        color: .pink
      )
    case .recommendationFromPodcast:
      return Data(
        text: "Preferred podcast",
        systemImageName: .recommendationFromPodcast,
        color: .blue
      )
    case .recommendationRecent:
      return Data(
        text: "Fresh",
        systemImageName: .recommendationRecent,
        color: .orange
      )
    case .similarityScore:
      return Data(
        text: "Similarity score",
        systemImageName: .recommendation,
        darkColor: .yellow,
        lightColor: .orange
      )
    case .tag:
      return Data(text: "Tag", systemImageName: .tag, color: .secondary)
    case .updated:
      return Data(text: "Updated", systemImageName: .calendar, color: .secondary)

    // UI Controls & Status
    case .navigateInto:
      return Data(text: "Navigate Into", systemImageName: .navigateInto, color: .secondary)
    case .clear:
      return Data(text: "Clear", systemImageName: .clear)
    case .clearSearch:
      return Data(text: "Clear Search", systemImageName: .clearSearch)
    case .downloadEpisode:
      return Data(text: "Download", systemImageName: .downloadEpisode, color: .blue)
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
        darkColor: .teal,
        lightColor: .blue
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
        darkColor: .teal,
        lightColor: .blue
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
        darkColor: .mint,
        lightColor: .green
      )
    case .sortByMostRecentlyQueued:
      return Data(
        text: "Most Recently Queued",
        systemImageName: .sortByMostRecentlyQueued,
        darkColor: .cyan,
        lightColor: .blue
      )
    case .sortByLeastRecentlyQueued:
      return Data(
        text: "Least Recently Queued",
        systemImageName: .sortByLeastRecentlyQueued,
        color: .brown
      )
    case .sortByRecentlyAdded:
      return Data(
        text: "Most Recently Added",
        systemImageName: .sortByRecentlyAdded,
        color: .orange
      )
    case .sortByRecentlyFinished:
      return Data(
        text: "Most Recently Finished",
        systemImageName: .sortByRecentlyFinished,
        color: .blue
      )
    case .sortByRecommendationScore:
      return Data(
        text: "Recommendation Score",
        systemImageName: .sortByRecommendationScore,
        darkColor: .yellow,
        lightColor: .orange
      )

    case .loading:
      return Data(text: "Loading", systemImageName: .loading)
    case .moreActions:
      return Data(text: "More Actions", systemImageName: .moreActions)
    case .nextChapter:
      return Data(text: "Next Chapter", systemImageName: .nextChapter, color: .blue)
    case .previousChapter:
      return Data(text: "Previous Chapter", systemImageName: .previousChapter, color: .blue)
    case .noEpisodeSelected:
      return Data(text: "No episode selected", systemImageName: .noEpisode)
    case .pauseButton:
      return Data(
        text: "Pause",
        systemImageName: .pauseButton,
        darkColor: .yellow,
        lightColor: .pink
      )
    case .playButton:
      return Data(text: "Play", systemImageName: .playButton, color: .green)
    case .seekBackward(let interval):
      return Data(
        text: "Seek Backward",
        systemImageName: SystemImageName(rawValue: "gobackward.\(interval)")
      )
    case .seekForward(let interval):
      return Data(
        text: "Seek Forward",
        systemImageName: SystemImageName(rawValue: "goforward.\(interval)")
      )
    case .finishEpisode:
      return Data(text: "Finish Episode", systemImageName: .finishEpisode, color: .blue)
    case .stopAfterEpisode:
      return Data(
        text: "Stop After This Episode",
        systemImageName: .stopAfterEpisode,
        color: .secondary
      )
    case .stopAfterEpisodeOn:
      return Data(
        text: "Stop After This Episode",
        systemImageName: .stopAfterEpisodeOn,
        color: .indigo
      )
    case .jumpToMaxPosition:
      return Data(
        text: "Resume Furthest Position",
        systemImageName: .jumpToMaxPosition,
        color: .accentColor
      )
    case .undoSeekBackward:
      return Data(
        text: "Undo Seek",
        systemImageName: .undoSeekBackward,
        darkColor: .orange,
        lightColor: .brown
      )
    case .undoSeekForward:
      return Data(
        text: "Undo Seek",
        systemImageName: .undoSeekForward,
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

    // Brand Links
    case .discord:
      return Data(text: "Discord", asset: "discord-mark", color: .primary)
    case .github:
      return Data(text: "GitHub", asset: "github-mark", color: .primary)

    // Manual Entry
    case .manualEntry:
      return Data(text: "Add Feed URL", systemImageName: .manualEntry, color: .purple)
    }
  }

  var rawLabel: Label<Text, Image> {
    Label {
      Text(textKey)
    } icon: {
      rawImage
    }
  }

  var rawImage: Image {
    switch data.source {
    case .system(let name): Image(systemName: name.rawValue)
    case .asset(let name): Image(name)
    }
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
    switch data.source {
    case .system(let name): name.rawValue
    case .asset: Assert.fatal("systemImageName is unavailable for asset-backed icon \(self)")
    }
  }

  func color(for colorScheme: ColorScheme) -> Color {
    colorScheme == .dark ? data.darkColor : data.lightColor
  }

  func label(_ text: String) -> some View {
    AppIconLabel(icon: self, textKey: LocalizedStringKey(text))
  }

  func label(_ text: LocalizedStringKey) -> some View {
    AppIconLabel(icon: self, textKey: text)
  }

  func rawLabel(_ text: String) -> Label<Text, Image> {
    Label {
      Text(LocalizedStringKey(text))
    } icon: {
      rawImage
    }
  }

  func rawLabel(_ text: LocalizedStringKey) -> Label<Text, Image> {
    Label {
      Text(text)
    } icon: {
      rawImage
    }
  }

  func labelButton(action: @MainActor @escaping () -> Void) -> some View {
    AppIconLabelButton(icon: self, action: action)
  }

  func labelButton(_ text: String, action: @MainActor @escaping () -> Void) -> some View {
    AppIconLabelButton(icon: self, textKey: LocalizedStringKey(text), action: action)
  }

  func labelButton(_ text: LocalizedStringKey, action: @MainActor @escaping () -> Void) -> some View
  {
    AppIconLabelButton(icon: self, textKey: text, action: action)
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

// MARK: - Recommendations

#if !WIDGET_EXTENSION
extension AppIcon {
  static func rating(for rating: EpisodeRating?) -> AppIcon {
    switch rating {
    case .loved: .loveEpisode
    case .liked: .likeEpisode
    case .disliked: .dislikeEpisode
    case .notInterested: .notInterestedEpisode
    case nil: .rateEpisode
    }
  }

  static func recommendationReason(for reason: RecommendationReason) -> AppIcon {
    if reason == .similarToLiked { return .recommendationSimilar }
    if reason == .podcastAffinity { return .recommendationFromPodcast }
    if reason == .recentlyPublished { return .recommendationRecent }

    Assert.fatal("Unknown recommendation reason: \(reason.rawValue)")
  }
}
#endif
