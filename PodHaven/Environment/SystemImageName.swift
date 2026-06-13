// Copyright Justin Bishop, 2025

import SwiftUI

@MainActor
struct SystemImageName:
  Equatable,
  Hashable,
  @MainActor RawRepresentable,
  Sendable
{
  let rawValue: String

  init(rawValue: String) {
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
  static let navigateInto = SystemImageName("chevron.right")
  static let podcastsList = SystemImageName("dot.radiowaves.left.and.right")
  static let search = SystemImageName("magnifyingglass")
  static let settings = SystemImageName("gear")
  static let showEpisode = SystemImageName("waveform")
  static let showPodcast = SystemImageName("antenna.radiowaves.left.and.right")

  // Actions
  static let addSmartList = SystemImageName("plus.circle")
  static let addTag = SystemImageName("plus.circle.fill")
  static let removeSmartListCondition = SystemImageName("minus.circle.fill")
  static let removeSmartListGroup = SystemImageName("minus.circle.fill")
  static let removeTag = SystemImageName("xmark.circle.fill")
  static let clear = SystemImageName("xmark.circle")
  static let clearSearch = SystemImageName("xmark")
  static let delete = SystemImageName("trash")
  static let failed = SystemImageName("x.circle")
  static let removeFromQueue = SystemImageName("minus.circle.fill")
  static let subscribe = SystemImageName("plus.circle")
  static let unsubscribe = SystemImageName("minus.circle")
  static let replaceQueue = SystemImageName("arrow.triangle.2.circlepath")

  // Documents & Data
  static let edit = SystemImageName("pencil.circle")
  static let selectAll = SystemImageName("checklist")

  // Episode Rating
  static let loveEpisode = SystemImageName("heart.fill")
  static let likeEpisode = SystemImageName("hand.thumbsup.fill")
  static let dislikeEpisode = SystemImageName("hand.thumbsdown.fill")
  static let notInterestedEpisode = SystemImageName("hand.raised.fill")
  static let rateEpisode = SystemImageName("hand.thumbsup")

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

  // Information Display
  static let aboutInfo = SystemImageName("questionmark.circle")
  static let tag = SystemImageName("tag")
  static let audioPlaceholder = SystemImageName("music.note")
  static let calendar = SystemImageName("calendar")
  static let duration = SystemImageName("clock")
  static let episodeCount = SystemImageName("number")
  static let error = SystemImageName("exclamationmark.triangle")
  static let noImage = SystemImageName("photo")
  static let publishDate = SystemImageName("calendar.badge.clock")
  static let recommendation = SystemImageName("sparkles")
  static let recommendationSimilar = SystemImageName("wand.and.stars")
  static let recommendationFromPodcast = SystemImageName("antenna.radiowaves.left.and.right")
  static let recommendationRecent = SystemImageName("flame.fill")
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
  static let nextChapter = SystemImageName("forward.frame.fill")
  static let noEpisode = SystemImageName("waveform.slash")
  static let pauseButton = SystemImageName("pause.circle.fill")
  static let play = SystemImageName("play.fill")
  static let playButton = SystemImageName("play.circle.fill")
  static let previousChapter = SystemImageName("backward.frame.fill")
  static let finishEpisode = SystemImageName("forward.end.fill")
  static let stopAfterEpisode = SystemImageName("moon.zzz")
  static let stopAfterEpisodeOn = SystemImageName("moon.zzz.fill")
  static let jumpToMaxPosition = SystemImageName("arrow.forward.to.line")
  static let undoSeekBackward = SystemImageName("arrow.uturn.backward")
  static let undoSeekForward = SystemImageName("arrow.uturn.forward")

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
  static let sortByRecentlyAdded = SystemImageName("calendar.badge.plus")
  static let sortByRecentlyFinished = SystemImageName("checkmark.circle.fill")
  static let sortByRecommendationScore = SystemImageName("sparkles")

  // Status Indicators
  static let waiting = SystemImageName("clock.arrow.circlepath")
  static let embeddingPending = SystemImageName("hourglass")
}
