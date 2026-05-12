// Copyright Justin Bishop, 2025

import FactoryKit
import Foundation
import GRDB
import IdentifiedCollections
import Logging
import Nuke
import SwiftUI
import Tagged
import UIKit

// Live state of `PodcastDetailViewModel`. Transitions flow through
// `transition(to:)` so view-facing projections stay in sync.
//
// - `.initial`: list-row snapshot (saved or savedSearchResult); promoted to
//   `.saved` once observation hydrates the series.
// - `.unsaved`: a podcast we know about but haven't persisted — feed-parsed,
//   shared-from-share-sheet, or an unsaved search result. May carry zero or
//   more pre-parsed episodes ready to be inserted on `subscribe()`.
// - `.saved`: a fully-hydrated series under live observation.
enum PodcastDetailState: Sendable {
  case initial(ListedPodcast)
  case unsaved(UnsavedPodcast, episodes: IdentifiedArrayOf<UnsavedEpisode>)
  case saved(PodcastSeriesDetail)

  var savedSeries: PodcastSeriesDetail? {
    guard case .saved(let series) = self else { return nil }
    return series
  }

  var detailContent: PodcastDetailContent {
    switch self {
    case .initial(let listed): return PodcastDetailContent(initial: listed)
    case .unsaved(let unsavedPodcast, _):
      return PodcastDetailContent(loaded: DisplayedPodcast(unsavedPodcast))
    case .saved(let series): return PodcastDetailContent(loaded: DisplayedPodcast(series.podcast))
    }
  }

  var feedURL: FeedURL {
    switch self {
    case .initial(let listed): return listed.feedURL
    case .unsaved(let unsavedPodcast, _): return unsavedPodcast.feedURL
    case .saved(let series): return series.podcast.feedURL
    }
  }

  var iTunesID: ITunesPodcastID? {
    switch self {
    case .initial(let listed): return listed.iTunesID
    case .unsaved(let unsavedPodcast, _): return unsavedPodcast.iTunesID
    case .saved(let series): return series.podcast.iTunesID
    }
  }

  var toString: String {
    switch self {
    case .initial(let listed): return "initial(\(listed.toString))"
    case .unsaved(let unsavedPodcast, let episodes):
      return "unsaved(\(unsavedPodcast.toString), episodes: \(episodes.count))"
    case .saved(let series): return "saved(\(series.toString))"
    }
  }
}

@Observable @MainActor
class PodcastDetailViewModel:
  DetailViewModel,
  ManagingEpisodes,
  SelectableEpisodeList,
  SortableEpisodeList
{
  @ObservationIgnored @DynamicInjected(\.alert) private var alert
  @ObservationIgnored @DynamicInjected(\.imagePipeline) private var imagePipeline
  @ObservationIgnored @DynamicInjected(\.observatory) private var observatory
  @ObservationIgnored @DynamicInjected(\.playManager) private var playManager
  @ObservationIgnored @DynamicInjected(\.queue) private var queue
  @ObservationIgnored @DynamicInjected(\.recommendationEngine) private var recommendationEngine
  @ObservationIgnored @DynamicInjected(\.refreshManager) private var refreshManager
  @ObservationIgnored @DynamicInjected(\.repo) private var repo
  @ObservationIgnored @DynamicInjected(\.sharedState) private var sharedState
  @ObservationIgnored @DynamicInjected(\.userNotificationManager) private
    var userNotificationManager

  private static let log = Log.as(LogSubsystem.PodcastsView.detail)
  private static let unavailableMessage = "This podcast is no longer available."

  // MARK: - State

  // `state` is the source of truth; `episodeList` is a one-way projection of it.
  private(set) var state: PodcastDetailState

  var podcast: PodcastDetailContent { state.detailContent }
  var saved: Bool { state.savedSeries != nil }

  // MARK: - ManagingEpisodes

  func getOrCreatePodcastEpisode(_ episode: ListedEpisode) async throws -> PodcastEpisode {
    let podcastEpisode = try await episode.getOrCreatePodcastEpisode()
    startObservation(podcastEpisode.podcast.id)
    return podcastEpisode
  }

  // MARK: - SelectableEpisodeList & SortableEpisodeList

  var episodeList = PowerList<ListedEpisode>(debounceDuration: .milliseconds(250))

  enum SortMethod: SortingMethod {
    case newestFirst
    case oldestFirst
    case recentlyAdded
    case longest
    case shortest
    case recentlyFinished
    case recentlyQueued
    case recommendationScore

    var appIcon: AppIcon {
      switch self {
      case .newestFirst:
        return .sortByNewest
      case .oldestFirst:
        return .sortByOldest
      case .recentlyAdded:
        return .sortByRecentlyAdded
      case .longest:
        return .sortByLongest
      case .shortest:
        return .sortByShortest
      case .recentlyFinished:
        return .sortByRecentlyFinished
      case .recentlyQueued:
        return .sortByMostRecentlyQueued
      case .recommendationScore:
        return .sortByRecommendationScore
      }
    }

    var sortMethod: (@Sendable (ListedEpisode, ListedEpisode) -> Bool)? {
      switch self {
      case .newestFirst:
        return { $0.pubDate > $1.pubDate }
      case .oldestFirst:
        return { $0.pubDate < $1.pubDate }
      case .recentlyAdded:
        return { lhs, rhs in
          let lhsDate = lhs.creationDate ?? Date.distantFuture
          let rhsDate = rhs.creationDate ?? Date.distantFuture
          return lhsDate > rhsDate
        }
      case .longest:
        return { $0.duration > $1.duration }
      case .shortest:
        return { $0.duration < $1.duration }
      case .recentlyFinished:
        return { lhs, rhs in
          let lhsDate = lhs.finishDate ?? Date.distantPast
          let rhsDate = rhs.finishDate ?? Date.distantPast
          return lhsDate > rhsDate
        }
      case .recentlyQueued:
        return { lhs, rhs in
          let lhsDate = lhs.queueDate ?? Date.distantPast
          let rhsDate = rhs.queueDate ?? Date.distantPast
          return lhsDate > rhsDate
        }
      case .recommendationScore:
        // Scoring is async; the view model installs the real closure once
        // `recommendationEngine.recommendations(for:)` returns.
        return nil
      }
    }

    var filterMethod: (@Sendable (ListedEpisode) -> Bool)? {
      switch self {
      case .recentlyFinished:
        return { $0.finished }
      case .recentlyQueued:
        return { $0.previouslyQueued }
      default: return nil
      }
    }
  }
  // `.recommendationScore` needs persisted `episodeID`s to score against the
  // engine; unsaved/initial states carry rows whose `episodeID` is nil and
  // would silently no-op the sort, so we hide the option until the series
  // is saved and observed.
  var allSortMethods: [SortMethod] {
    guard saved else {
      return SortMethod.allCases.filter { $0 != .recommendationScore }
    }
    return SortMethod.allCases
  }
  var currentSortMethod: SortMethod = .newestFirst {
    didSet {
      guard oldValue != currentSortMethod else { return }
      episodeList.filterMethod = currentSortMethod.filterMethod
      if currentSortMethod == .recommendationScore {
        startRecommendationSort()
      } else {
        stopRecommendationSort()
        episodeList.sortMethod = currentSortMethod.sortMethod
      }
    }
  }

  var selectedPodcastEpisodes: [PodcastEpisode] {
    get async throws {
      let selectedEpisodes = self.selectedEpisodes
      guard !selectedEpisodes.isEmpty else { return [] }

      Self.log.debug("selectedPodcastEpisodes: \(selectedEpisodes.count) episodes selected")

      let savedEpisodeIDs = selectedEpisodes.compactMap(\.episodeID)
      let unsavedPodcastEpisodes = selectedEpisodes.compactMap(\.unsavedPodcastEpisode)
      let savedByID = Dictionary(
        uniqueKeysWithValues: try await repo.podcastEpisodes(savedEpisodeIDs).map { ($0.id, $0) }
      )
      let upsertedByMediaGUID = Dictionary(
        uniqueKeysWithValues: try await repo.upsertPodcastEpisodes(unsavedPodcastEpisodes)
          .map { ($0.mediaGUID, $0) }
      )
      // Walk `selectedEpisodes` (PowerList visible order) to interleave
      // saved + just-upserted rows in user-visible order.
      let podcastEpisodes: [PodcastEpisode] = selectedEpisodes.compactMap { episode in
        if let episodeID = episode.episodeID { return savedByID[episodeID] }
        return upsertedByMediaGUID[episode.mediaGUID]
      }

      // No matches with non-empty selection means rows vanished under the user
      // (e.g. cascade delete) — surface a no-op instead of crashing.
      guard let firstEpisode = podcastEpisodes.first else {
        Self.log.error(
          """
          selectedPodcastEpisodes: \(selectedEpisodes.count) selected but no \
          matching rows (saved hits: \(savedByID.count), upsert hits: \
          \(upsertedByMediaGUID.count))
          """
        )
        alert("These episodes are no longer available.")
        return []
      }
      startObservation(firstEpisode.podcast.id)

      return podcastEpisodes
    }
  }

  // MARK: - Derived State

  var displayingAboutSection: Bool = false
  var showingSettings: Bool = false

  // Non-nil iff `.saved`. `.initial` has no settings columns on the list row;
  // `.unsaved` has `UnsavedPodcast` defaults but no `Podcast.ID` to write back
  // to, so the settings sheet refuses to open there. This matches the toolbar
  // gating in `PodcastDetailView` exactly.
  var settings: PodcastSettings? { state.savedSeries?.podcast.unsaved.settings }

  func updateSettings(_ newSettings: PodcastSettings) {
    guard let podcastID = state.savedSeries?.id else {
      Self.log.warning("Cannot update settings for unsaved podcast")
      return
    }
    let previouslyNotifying = settings?.notifyNewEpisodes ?? false

    runTask("updateSettings: podcast \(podcastID)") { [self] in
      try await repo.updatePodcastSettings(podcastID, newSettings)
      if newSettings.notifyNewEpisodes, !previouslyNotifying {
        await userNotificationManager.requestAuthorizationIfNeeded()
      }
    }
  }

  var inferredFreshnessCadence: FreshnessCadence {
    FreshnessCadence.infer(from: episodeList.allEntries.map(\.pubDate))
  }

  var episodesLoaded: Bool { !episodeList.allEntries.isEmpty }

  var tags: IdentifiedArrayOf<Tag> { state.savedSeries?.tags ?? [] }
  var allTags: IdentifiedArrayOf<Tag> { sharedState.tags }

  var mostRecentEpisodeDate: Date {
    episodeList.allEntries.first?.pubDate ?? Date.epoch
  }

  // MARK: - Share

  var shareURL: URL? { ShareURL.podcast(feedURL: podcast.feedURL) }
  private var shareArtwork: UIImage?

  var sharePreview: SharePreview<Image, Image> {
    let image = sharePreviewImage
    return SharePreview(Text(podcast.title), image: image, icon: image)
  }

  private var sharePreviewImage: Image {
    guard let shareArtwork else { return AppIcon.showPodcast.rawImage }
    return Image(uiImage: shareArtwork)
  }

  // MARK: - Initialization

  private init(state: PodcastDetailState) {
    self.state = state
    episodeList.sortMethod = currentSortMethod.sortMethod
    refreshEpisodeList(from: state)

    Task { [weak self] in
      guard let self else { return }

      do {
        shareArtwork = try await imagePipeline.image(for: podcast.image)
      } catch {
        Self.log.caughtError(
          "init: failed to load share artwork for \(podcast.image)",
          error,
          level: { _ in .info }
        )
      }
    }
  }

  convenience init(podcast: DisplayedPodcast) {
    switch podcast.source {
    case .saved(let savedPodcast):
      self.init(state: .saved(PodcastSeriesDetail(podcast: savedPodcast)))
    case .unsaved(let unsavedPodcast):
      self.init(state: .unsaved(unsavedPodcast, episodes: []))
    }
  }

  convenience init(listedPodcast: ListedPodcast) {
    if let unsavedPodcast = listedPodcast.unsavedSearchResult {
      self.init(state: .unsaved(unsavedPodcast, episodes: []))
    } else {
      self.init(state: .initial(listedPodcast))
    }
  }

  convenience init(unsavedPodcastSeries: UnsavedPodcastSeries) {
    self.init(
      state: .unsaved(
        unsavedPodcastSeries.unsavedPodcast,
        episodes: unsavedPodcastSeries.unsavedEpisodes
      )
    )
  }

  func performAppear() async throws {
    if try await attemptObservation() { return }

    Self.log.debug("\(state.toString) does not exist in db")

    guard episodeList.allEntries.isEmpty else {
      Self.log.debug("PodcastDetailViewModel already has entries, no need to fetch again.")
      return
    }

    try await loadPresentationFromFeed()

    Self.log.debug("Attempting observation again in case FeedURL got updated by parsing the feed")
    try await attemptObservation()
  }

  // MARK: - Public Methods

  func subscribe() {
    runTask("subscribe: \(state.toString)") { [self] in
      switch state {
      case .saved(let series):
        try await repo.markSubscribed(series.id)
      case .initial(let listedPodcast):
        guard
          let series = try await repo.podcastSeriesDetail(
            listedPodcast.feedURL,
            iTunesID: listedPodcast.iTunesID
          )
        else {
          Self.log.warning("subscribe: no saved series for initial \(listedPodcast.toString)")
          return
        }
        transition(to: .saved(series))
        startObservation(series.id)
        try await repo.markSubscribed(series.id)
      case .unsaved(let unsavedPodcast, let episodes):
        if let series = try await repo.podcastSeriesDetail(
          unsavedPodcast.feedURL,
          iTunesID: unsavedPodcast.iTunesID
        ) {
          transition(to: .saved(series))
          startObservation(series.id)
          try await repo.markSubscribed(series.id)
        } else {
          let inserted = try await repo.insertSeries(
            UnsavedPodcastSeries(unsavedPodcast: unsavedPodcast, unsavedEpisodes: episodes)
          )
          transition(to: .saved(inserted.toDetail()))
          startObservation(inserted.id)
          try await repo.markSubscribed(inserted.id)
        }
      }
    }
  }

  func unsubscribe() {
    runTask("unsubscribe: \(state.toString)") { [self] in
      guard let podcastID = try await ensureObservedSeries()
      else {
        Self.log.warning("Trying to unsubscribe from a non-saved podcast")
        return
      }

      try await repo.markUnsubscribed(podcastID)
    }
  }

  func delete() {
    runTask("delete: \(state.toString)") { [self] in
      guard let podcastID = try await ensureObservedSeries()
      else {
        Self.log.warning("Trying to delete a non-saved podcast")
        return
      }

      Self.log.info("Deleting podcast: \(state.toString)")
      try await repo.deletePodcast(podcastID)
    }
  }

  func refreshSeries() async {
    do {
      if let series = state.savedSeries,
        let operationalSeries = try await repo.podcastSeries(series.id)
      {
        Self.log.debug("refreshing saved podcast series \(operationalSeries.toString)")
        try await refreshManager.refreshSeries(podcastSeries: operationalSeries)
      } else {
        Self.log.debug("refreshing unsaved podcast series \(state.toString)")
        try await loadPresentationFromFeed()
      }
    } catch {
      Self.log.caughtError("refreshSeries: failed for \(state.toString)", error)
      guard ErrorKit.isRemarkable(error) else { return }
      alert(ErrorKit.message(for: error))
    }
  }

  // MARK: - Tag Management

  func addTag(_ tagID: Tag.ID) {
    guard let podcastID = state.savedSeries?.id else {
      Self.log.warning("Cannot add tag to unsaved podcast")
      return
    }

    runTask("addTag: \(tagID) to podcast \(podcastID)") { [self] in
      try await repo.addTag(tagID, to: podcastID)
    }
  }

  func removeTag(_ tagID: Tag.ID) {
    guard let podcastID = state.savedSeries?.id else {
      Self.log.warning("Cannot remove tag from unsaved podcast")
      return
    }

    runTask("removeTag: \(tagID) from podcast \(podcastID)") { [self] in
      try await repo.removeTag(tagID, from: podcastID)
    }
  }

  // MARK: - Observation Management

  @ObservationIgnored private var observationTask: Task<Void, Never>?

  @discardableResult
  private func attemptObservation() async throws -> Bool {
    if let observationTask, !observationTask.isCancelled {
      Self.log.debug("Observation already active; not attempting observation")
      return true
    }

    guard let savedSeries = try await savedSeriesForCurrentState() else { return false }

    Self.log.debug("\(savedSeries.toString) exists in db")

    // Soft migration: backfill iTunesID for pre-existing podcasts
    if savedSeries.podcast.iTunesID == nil, let iTunesID = state.iTunesID {
      try await repo.updateITunesID(savedSeries.podcast.id, iTunesID: iTunesID)
    }

    transition(to: .saved(savedSeries))
    startObservation(savedSeries.id)

    Task { [weak self] in
      guard let self else { return }
      await refreshSeries()
    }

    return true
  }

  private func startObservation(_ podcastID: Podcast.ID) {
    if let observationTask, !observationTask.isCancelled {
      Self.log.debug("Observation already active; not starting observation")
      return
    }

    observationTask = Task { [weak self] in
      guard let self else { return }
      do {
        try await observePodcastSeries(podcastID)
      } catch {
        Self.log.caughtError("startObservation: failed for podcast \(podcastID)", error)
      }
      clearObservationTask()
    }
  }

  private func observePodcastSeries(_ podcastID: Podcast.ID) async throws {
    Self.log.debug("Observing podcast series with ID: \(podcastID)")

    for try await updatedSeries in observatory.podcastSeriesDetail(podcastID) {
      try Task.checkCancellation()

      Self.log.debug("Updating observed series: \(String(describing: updatedSeries?.toString))")

      guard let updatedSeries
      else {
        Self.log.debug("Podcast was deleted")
        do {
          try await loadPresentationFromFeed()
        } catch {
          Self.log.caughtError(
            "observePodcastSeries: failed to re-parse feed after podcast \(podcastID) was deleted",
            error
          )
          alert(Self.unavailableMessage)
        }
        return
      }

      guard updatedSeries != state.savedSeries
      else {
        Self.log.debug("New podcastSeries is the same as the current one, skipping update")
        continue
      }

      transition(to: .saved(updatedSeries))
    }
  }

  // MARK: - Recommendation Sort

  @ObservationIgnored private var recommendationSortTask: Task<Void, Never>?

  private func startRecommendationSort() {
    recommendationSortTask?.cancel()
    recommendationSortTask = Task { [weak self] in
      guard let self else { return }
      for await _ in recommendationEngine.$contextRevision.stream() {
        guard !Task.isCancelled else { return }
        await fetchAndApplyRecommendationScores()
      }
    }
  }

  private func stopRecommendationSort() {
    recommendationSortTask?.cancel()
    recommendationSortTask = nil
  }

  private func fetchAndApplyRecommendationScores() async {
    let episodeIDs = episodeList.allEntries.compactMap(\.episodeID)
    guard !episodeIDs.isEmpty else { return }

    let scoreMap: [Episode.ID: RecommendationScore]
    do {
      let podcastEpisodes = try await repo.podcastEpisodes(episodeIDs)
      scoreMap = try await recommendationEngine.recommendations(
        for: podcastEpisodes.map(\.episode)
      )
    } catch {
      Self.log.caughtError(
        "fetchAndApplyRecommendationScores failed for \(episodeIDs.count) ids",
        error
      )
      return
    }

    guard currentSortMethod == .recommendationScore else { return }
    let valuesByID = scoreMap.mapValues(\.value)
    episodeList.sortMethod = { lhs, rhs in
      let lhsScore = lhs.episodeID.flatMap { valuesByID[$0] } ?? 0
      let rhsScore = rhs.episodeID.flatMap { valuesByID[$0] } ?? 0
      return RecommendationOrder.descending(
        .init(score: lhsScore, pubDate: lhs.pubDate, mediaGUID: lhs.mediaGUID),
        .init(score: rhsScore, pubDate: rhs.pubDate, mediaGUID: rhs.mediaGUID)
      )
    }
  }

  // MARK: - Disappear

  func disappear() {
    Self.log.debug("disappear: executing")
    clearObservationTask()
    stopRecommendationSort()
  }

  private func clearObservationTask() {
    observationTask?.cancel()
    observationTask = nil
  }

  // MARK: - Private Helpers

  private func transition(to newState: PodcastDetailState) {
    Self.log.debug("transitioning state \(state.toString) → \(newState.toString)")
    state = newState
    refreshEpisodeList(from: newState)
  }

  private func refreshEpisodeList(from state: PodcastDetailState) {
    switch state {
    case .initial:
      // List rows are not bundled with the bootstrap snapshot; observation
      // populates `episodeList` once the saved series hydrates.
      return
    case .unsaved(let unsavedPodcast, let episodes):
      episodeList.allEntries = IdentifiedArray(
        uniqueElements: episodes.map { unsavedEpisode in
          ListedEpisode(
            UnsavedPodcastEpisode(
              unsavedPodcast: unsavedPodcast,
              unsavedEpisode: unsavedEpisode
            )
          )
        }
      )
    case .saved(let series):
      episodeList.allEntries = IdentifiedArray(
        uniqueElements: series.episodes.map { listableEpisode in
          ListedEpisode(
            ListablePodcastEpisode(podcast: series.podcast, episode: listableEpisode)
          )
        }
      )
    }
  }

  @discardableResult
  private func ensureObservedSeries() async throws -> Podcast.ID? {
    if let podcastID = state.savedSeries?.id { return podcastID }

    guard let savedSeries = try await savedSeriesForCurrentState() else { return nil }

    transition(to: .saved(savedSeries))
    startObservation(savedSeries.id)
    return savedSeries.id
  }

  private func loadPresentationFromFeed() async throws {
    Self.log.debug("Now fetching and parsing feed for \(state.toString)")
    let feedURL = state.feedURL
    let iTunesID = state.iTunesID
    let podcastFeed = try await PodcastFeed.parse(feedURL)
    let unsavedPodcast = try podcastFeed.toUnsavedPodcast(iTunesID: iTunesID)
    transition(
      to: .unsaved(
        unsavedPodcast,
        episodes: IdentifiedArrayOf(uniqueElements: podcastFeed.toUnsavedEpisodes())
      )
    )
  }

  private func savedSeriesForCurrentState() async throws -> PodcastSeriesDetail? {
    try await repo.podcastSeriesDetail(state.feedURL, iTunesID: state.iTunesID)
  }
}
