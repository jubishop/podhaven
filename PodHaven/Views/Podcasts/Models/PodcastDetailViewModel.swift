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
enum PodcastDetailState: Equatable, Sendable, Stringable {
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
  @ObservationIgnored @DynamicInjected(\.contextualEmbedding) private var contextualEmbedding
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
        // Scoring is async; the recommendation coordinator installs the real
        // comparator once the recommendation scores land.
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
  var allSortMethods: [SortMethod] { SortMethod.allCases }
  var currentSortMethod: SortMethod = .newestFirst {
    didSet {
      guard oldValue != currentSortMethod else { return }
      episodeList.filterMethod = currentSortMethod.filterMethod
      if currentSortMethod == .recommendationScore {
        startRecommendationObservation()
      } else {
        episodeList.sortMethod = currentSortMethod.sortMethod
        recommendationCoordinator.cancel()
      }
    }
  }

  var selectedPodcastEpisodes: [PodcastEpisode] {
    get async throws {
      let selectedEpisodes = self.selectedEpisodes
      guard !selectedEpisodes.isEmpty else { return [] }

      Self.log.debug("selectedPodcastEpisodes: \(selectedEpisodes.count) episodes selected")

      let savedEpisodeIDs = selectedEpisodes.compactMap(\.episodeID)
      let unsavedPodcastEpisodes = selectedEpisodes.compactMap(\.unsaved)
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

  // MARK: - Recommendations

  @ObservationIgnored
  private var unsavedEmbeddingCache:
    (revision: Int, vectors: [MediaGUID: (source: String, vector: [Float])])?

  private struct RecommendationScoringSnapshot: Equatable, Sendable {
    let scoringRevision: Int
    let state: State
    let entries: Set<Entry>

    enum State: Hashable, Sendable {
      case unsaved(embeddingRevision: Int)
      case saved(Podcast.ID)
    }

    enum Entry: Hashable, Sendable {
      case saved(mediaGUID: MediaGUID, episodeID: Episode.ID, pubDate: Date)
      case unsaved(mediaGUID: MediaGUID, embeddingSource: String)
      case unscored(mediaGUID: MediaGUID)
    }
  }

  private struct RecommendationPass: Sendable {
    enum Kind: Sendable { case saved, unsaved }

    let kind: Kind
    let values: [MediaGUID: Float]

    static func empty(for state: RecommendationScoringSnapshot.State) -> RecommendationPass {
      switch state {
      case .saved: return RecommendationPass(kind: .saved, values: [:])
      case .unsaved: return RecommendationPass(kind: .unsaved, values: [:])
      }
    }
  }

  @ObservationIgnored
  private lazy var recommendationCoordinator = RecommendationScoringCoordinator<
    RecommendationScoringSnapshot, RecommendationPass
  >(
    makeSnapshot: { [weak self] in
      guard let self, currentSortMethod == .recommendationScore else { return nil }
      return currentRecommendationScoringSnapshot()
    },
    score: { [weak self] in
      guard let self, let snapshotState = currentSnapshotState()
      else { return .cancelled }
      let entries = episodeList.allEntries
      do {
        let (pass, cacheable) = try await computeRecommendationScores(
          for: snapshotState,
          entries: entries
        )
        return cacheable ? .cacheable(pass) : .uncacheable(pass)
      } catch is CancellationError {
        return .cancelled
      } catch {
        Self.log.caughtError("recommendation scoring failed", error)
        return .uncacheable(.empty(for: snapshotState))
      }
    },
    apply: { [weak self] in
      guard let self else { return }
      applyRecommendationScores($0)
    },
    refreshOnAssetsLoaded: true
  )

  private func startRecommendationObservation() {
    recommendationCoordinator.startObservations()
    recommendationCoordinator.refresh()
  }

  private func currentRecommendationScoringSnapshot() -> RecommendationScoringSnapshot? {
    guard let snapshotState = currentSnapshotState() else { return nil }
    return RecommendationScoringSnapshot(
      scoringRevision: recommendationEngine.scoringRevision,
      state: snapshotState,
      entries: Set(episodeList.allEntries.map(scoringSnapshotEntry))
    )
  }

  private func currentSnapshotState() -> RecommendationScoringSnapshot.State? {
    switch state {
    case .initial:
      return nil
    case .unsaved:
      return .unsaved(embeddingRevision: contextualEmbedding.revision)
    case .saved(let series):
      return .saved(series.id)
    }
  }

  private func scoringSnapshotEntry(
    _ episode: ListedEpisode
  ) -> RecommendationScoringSnapshot.Entry {
    if let episodeID = episode.episodeID {
      return .saved(
        mediaGUID: episode.mediaGUID,
        episodeID: episodeID,
        pubDate: episode.pubDate
      )
    }
    if let unsaved = episode.unsaved {
      return .unsaved(
        mediaGUID: episode.mediaGUID,
        embeddingSource: unsaved.searchableString
      )
    }
    return .unscored(mediaGUID: episode.mediaGUID)
  }

  private func computeRecommendationScores(
    for snapshotState: RecommendationScoringSnapshot.State,
    entries: IdentifiedArrayOf<ListedEpisode>
  ) async throws -> (RecommendationPass, cacheable: Bool) {
    guard !entries.isEmpty else { return (.empty(for: snapshotState), true) }

    switch snapshotState {
    case .saved(let podcastID):
      let values = try await savedRecommendationScores(podcastID: podcastID, entries: entries)
      return (RecommendationPass(kind: .saved, values: values), true)
    case .unsaved:
      let (values, cacheable) = try await unsavedSimilarityScores(entries: entries)
      return (RecommendationPass(kind: .unsaved, values: values), cacheable)
    }
  }

  private func savedRecommendationScores(
    podcastID: Podcast.ID,
    entries: IdentifiedArrayOf<ListedEpisode>
  ) async throws -> [MediaGUID: Float] {
    var candidates = [CandidateEpisode](capacity: entries.count)
    var mediaGUIDByEpisodeID = [Episode.ID: MediaGUID](capacity: entries.count)
    for episode in entries {
      guard let episodeID = episode.episodeID else { continue }
      candidates.append(
        CandidateEpisode(id: episodeID, podcastID: podcastID, pubDate: episode.pubDate)
      )
      mediaGUIDByEpisodeID[episodeID] = episode.mediaGUID
    }
    guard !candidates.isEmpty else { return [:] }

    let scoreMap = try await recommendationEngine.recommendations(for: candidates)

    var result = [MediaGUID: Float](capacity: scoreMap.count)
    for (episodeID, score) in scoreMap {
      guard let mediaGUID = mediaGUIDByEpisodeID[episodeID] else { continue }
      result[mediaGUID] = score.value
    }
    return result
  }

  private func unsavedSimilarityScores(
    entries: IdentifiedArrayOf<ListedEpisode>
  ) async throws -> ([MediaGUID: Float], cacheable: Bool) {
    await contextualEmbedding.loadAssetsIfAvailable()
    guard contextualEmbedding.assetsLoaded.isFinished else { return ([:], false) }

    let revision = contextualEmbedding.revision
    var cachedVectors: [MediaGUID: (source: String, vector: [Float])]
    if let cache = unsavedEmbeddingCache, cache.revision == revision {
      cachedVectors = cache.vectors
    } else {
      cachedVectors = [MediaGUID: (source: String, vector: [Float])](capacity: entries.count)
    }

    var result = [MediaGUID: Float](capacity: entries.count)
    for episode in entries {
      try Task.checkCancellation()
      guard let unsavedPodcastEpisode = episode.unsaved else { continue }
      let source = unsavedPodcastEpisode.searchableString
      let vector: [Float]
      if let cached = cachedVectors[episode.mediaGUID], cached.source == source {
        vector = cached.vector
      } else {
        vector = try await EmbeddingService.embeddingVector(
          for: unsavedPodcastEpisode,
          embedding: contextualEmbedding
        )
        cachedVectors[episode.mediaGUID] = (source: source, vector: vector)
      }
      if let similarity = recommendationEngine.similarityScore(forEmbedding: vector) {
        result[episode.mediaGUID] = similarity
      }
    }

    unsavedEmbeddingCache = (revision: revision, vectors: cachedVectors)
    return (result, true)
  }

  private func applyRecommendationScores(_ pass: RecommendationPass) {
    let values = pass.values
    switch pass.kind {
    case .saved:
      episodeList.filterMethod = { values[$0.mediaGUID] != nil }
    case .unsaved:
      episodeList.filterMethod = currentSortMethod.filterMethod
    }
    episodeList.sortMethod = { lhs, rhs in
      let lhsScore = values[lhs.mediaGUID] ?? 0
      let rhsScore = values[rhs.mediaGUID] ?? 0
      if lhsScore != rhsScore { return lhsScore > rhsScore }
      if lhs.pubDate != rhs.pubDate { return lhs.pubDate > rhs.pubDate }
      if lhs.mediaGUID.guid != rhs.mediaGUID.guid {
        return lhs.mediaGUID.guid > rhs.mediaGUID.guid
      }
      return lhs.mediaGUID.mediaURL.rawValue.absoluteString
        > rhs.mediaGUID.mediaURL.rawValue.absoluteString
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
    startObservation(state.savedSeries?.id)

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
    if currentSortMethod == .recommendationScore {
      startRecommendationObservation()
    }

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
        try await repo.markSubscribed(series.id)
      case .unsaved(let unsavedPodcast, let episodes):
        if let series = try await repo.podcastSeriesDetail(
          unsavedPodcast.feedURL,
          iTunesID: unsavedPodcast.iTunesID
        ) {
          transition(to: .saved(series))
          try await repo.markSubscribed(series.id)
        } else {
          let inserted = try await repo.insertSeries(
            UnsavedPodcastSeries(unsavedPodcast: unsavedPodcast, unsavedEpisodes: episodes)
          )
          transition(to: .saved(inserted.toDetail()))
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

  @ObservationIgnored var observationTask: Task<Void, Never>?

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

    Task { [weak self] in
      guard let self else { return }
      await refreshSeries()
    }

    return true
  }

  private func startObservation(_ podcastID: Podcast.ID? = nil) {
    guard let podcastID else { return }

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
    }
  }

  private func observePodcastSeries(_ podcastID: Podcast.ID) async throws {
    Self.log.debug("Observing podcast series with ID: \(podcastID)")

    // Clear our reference on any natural exit (deletion, error, normal end).
    // Skip when we were cancelled — disappear() or a re-binding
    // startObservation() has already cleared/replaced observationTask, and
    // stomping it would kill a newer task.
    defer {
      if !Task.isCancelled {
        observationTask = nil
      }
    }

    for try await updatedSeries in observatory.podcastSeriesDetail(podcastID) {
      try Task.checkCancellation()

      Self.log.debug("Updating observed series: \(String(describing: updatedSeries?.toString))")

      guard let updatedSeries
      else {
        Self.log.debug("Podcast was deleted")
        // Post-deletion strategy: re-parse the RSS feed so the UI can
        // recover to an unsaved snapshot. This diverges from
        // `EpisodeDetailViewModel`, which converts the cached
        // `PodcastEpisode` directly via `toOriginalUnsavedPodcastEpisode()`:
        // podcasts have a per-feed RSS endpoint we can fall back to, but
        // episodes don't. The trade-off is a brief loading state while
        // the feed is re-parsed, in exchange for fresh fields.
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

  // MARK: - Disappear

  func disappear() {
    Self.log.debug("disappear: executing")
    clearObservationTask()
    recommendationCoordinator.cancel()
  }

  // MARK: - Private Helpers

  private func transition(to newState: PodcastDetailState) {
    guard newState != state else { return }
    logStateTransition(to: newState)
    state = newState
    refreshEpisodeList(from: newState)
    startObservation(newState.savedSeries?.id)
    recommendationCoordinator.refresh()
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
