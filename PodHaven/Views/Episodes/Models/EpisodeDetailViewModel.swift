// Copyright Justin Bishop, 2026

import AVFoundation
import FactoryKit
import Foundation
import GRDB
import IdentifiedCollections
import Logging
import SwiftUI
import Tagged

// Live state of `EpisodeDetailViewModel`. Transitions flow through
// `transition(to:)` so the view-facing projection (`episode`) stays in sync.
//
// - `.initial`: list-row snapshot (saved listed episode whose `PodcastEpisode`
//   has not been loaded). Promotes to `.saved` once `performAppear` finds it,
//   or causes a dismiss if the row has been deleted.
// - `.unsaved`: an episode we know about but haven't persisted; either an
//   unsaved-source displayed/listed episode or a saved episode that was
//   reverted after observation reported deletion.
// - `.saved`: a fully-saved episode under live observation.
enum EpisodeDetailState: Equatable, Sendable, Stringable {
  case initial(ListedEpisode)
  case unsaved(UnsavedPodcastEpisode)
  case saved(PodcastEpisode)

  var savedPodcastEpisode: PodcastEpisode? {
    guard case .saved(let podcastEpisode) = self else { return nil }
    return podcastEpisode
  }

  var detailContent: EpisodeDetailContent {
    switch self {
    case .initial(let listed): return EpisodeDetailContent(initial: listed)
    case .unsaved(let unsaved): return EpisodeDetailContent(loaded: DisplayedEpisode(unsaved))
    case .saved(let podcastEpisode):
      return EpisodeDetailContent(loaded: DisplayedEpisode(podcastEpisode))
    }
  }

  var mediaGUID: MediaGUID {
    switch self {
    case .initial(let listed): return listed.mediaGUID
    case .unsaved(let unsaved): return unsaved.mediaGUID
    case .saved(let podcastEpisode): return podcastEpisode.mediaGUID
    }
  }

  var toString: String {
    switch self {
    case .initial(let listed): return "initial(\(listed.toString))"
    case .unsaved(let unsaved): return "unsaved(\(unsaved.toString))"
    case .saved(let podcastEpisode): return "saved(\(podcastEpisode.toString))"
    }
  }

  enum Kind: Sendable {
    case initial
    case unsaved
    case saved
  }

  var kind: Kind {
    switch self {
    case .initial: .initial
    case .unsaved: .unsaved
    case .saved: .saved
    }
  }
}

enum EpisodeDetailDisplayedScore: Sendable {
  case recommendation(RecommendationScore)
  case similarity(Float)
  case embeddingPending
}

@Observable @MainActor class EpisodeDetailViewModel: DetailViewModel {
  @ObservationIgnored @DynamicInjected(\.alert) private var alert
  @ObservationIgnored @DynamicInjected(\.cacheManager) private var cacheManager
  @ObservationIgnored @DynamicInjected(\.contextualEmbedding) private var contextualEmbedding
  @ObservationIgnored @DynamicInjected(\.navigation) private var navigation
  @ObservationIgnored @DynamicInjected(\.observatory) private var observatory
  @ObservationIgnored @DynamicInjected(\.playManager) private var playManager
  @ObservationIgnored @DynamicInjected(\.queue) private var queue
  @ObservationIgnored @DynamicInjected(\.recommendationEngine) private var recommendationEngine
  @ObservationIgnored @DynamicInjected(\.recommendationRepo) private var recommendationRepo
  @ObservationIgnored @DynamicInjected(\.repo) private var repo
  @ObservationIgnored @DynamicInjected(\.sharedState) private var sharedState
  @ObservationIgnored @DynamicInjected(\.taskPriority) private var taskPriority

  private static let log = Log.as(LogSubsystem.EpisodesView.detail)

  // MARK: - State

  private let originTab: Navigation.Tab
  private(set) var state: EpisodeDetailState
  var tags: IdentifiedArrayOf<Tag> = []
  private var score: EpisodeDetailDisplayedScore?

  var episode: EpisodeDetailContent { state.detailContent }

  // MARK: - Derived State

  var onDeck: Bool {
    guard let podcastEpisode = state.savedPodcastEpisode else { return false }
    return sharedState.onDeck?.id == podcastEpisode.id
  }

  var atTopOfQueue: Bool {
    episode.queueOrder == 0
  }

  var atBottomOfQueue: Bool {
    guard let queueOrder = episode.queueOrder else { return false }
    return queueOrder == sharedState.maxQueuePosition
  }

  var isPlaying: Bool {
    guard let podcastEpisode = state.savedPodcastEpisode else { return false }
    return sharedState.isEpisodePlaying(podcastEpisode)
  }

  var canClearCache: Bool {
    episode.cacheStatus != .uncached && CacheManager.canClearCache(episode)
  }

  // Hide the score once the user has rated or finished the episode: a
  // direct rating outweighs similarity-to-liked, and a finished episode
  // is itself a signal — its own score is circular.
  var displayedScore: EpisodeDetailDisplayedScore? {
    guard episode.rating == nil, !episode.finished else { return nil }
    return score
  }

  private let startTime: Int?

  // MARK: - Initialization

  private init(state: EpisodeDetailState, startTime: Int? = nil) {
    self.originTab = Container.shared.navigation().currentTab
    self.state = state
    self.startTime = startTime
  }

  convenience init(episode: DisplayedEpisode, startTime: Int? = nil) {
    switch episode.source {
    case .saved(let podcastEpisode):
      self.init(state: .saved(podcastEpisode), startTime: startTime)
    case .unsaved(let unsavedPodcastEpisode):
      self.init(state: .unsaved(unsavedPodcastEpisode), startTime: startTime)
    }
  }

  convenience init(listedEpisode: ListedEpisode) {
    if let unsavedPodcastEpisode = listedEpisode.unsaved {
      self.init(state: .unsaved(unsavedPodcastEpisode))
    } else {
      self.init(state: .initial(listedEpisode))
    }
  }

  func performAppear() async throws {
    let podcastEpisode = try await repo.podcastEpisode(state.mediaGUID)

    if let podcastEpisode {
      Self.log.debug("Podcast episode: \(podcastEpisode.toString) exists in db")

      transition(to: .saved(podcastEpisode))
      startObservation(podcastEpisode)
    } else {
      Self.log.debug("Podcast episode: \(state.toString) does not exist in db")

      switch state {
      case .initial:
        // Saved-listed seed but the row is gone — only safe move is to
        // dismiss; the bridge can't synthesize an unsaved fallback.
        Self.log.warning("Episode no longer exists for detail hydration: \(state.toString)")
        alert("This episode is no longer available.")
        navigation.dismiss(from: originTab)
        return
      case .unsaved:
        // Already in unsaved state; nothing to revert.
        break
      case .saved(let stalePodcastEpisode):
        // Saved-source seed pointing at a row that's been deleted between
        // navigation and appear; same behavior as `.initial` — dismiss.
        Self.log.warning(
          "Saved-source seed missing from DB: \(stalePodcastEpisode.toString)"
        )
        alert("This episode is no longer available.")
        navigation.dismiss(from: originTab)
        return
      }
    }

    startRecommendationObservation()

    if let startTime {
      Self.log.debug("Auto-playing from startTime: \(startTime)s")
      let podcastEpisode = try await getOrCreatePodcastEpisode()
      try await loadAndPlay(podcastEpisode, seekTo: startTime)
    }
  }

  // MARK: - Public Methods

  func playNow() {
    runTask("playNow: \(state.toString)") { [self] in
      let podcastEpisode = try await getOrCreatePodcastEpisode()
      try await playManager.load(podcastEpisode)
      await playManager.play()
    }
  }

  func playAt(timestamp: String) {
    guard let seconds = Timestamp.parse(timestamp) else {
      Self.log.warning("Failed to parse timestamp: \(timestamp)")
      return
    }

    runTask("playAt: \(state.toString) at timestamp \(timestamp)") { [self] in
      let podcastEpisode = try await getOrCreatePodcastEpisode()
      try await loadAndPlay(podcastEpisode, seekTo: seconds)
    }
  }

  func pause() {
    guard isPlaying else { return }

    Task { [weak self] in
      guard let self else { return }
      await playManager.pause()
    }
  }

  func addToTopOfQueue() {
    guard !atTopOfQueue else { return }

    runTask("addToTopOfQueue: \(state.toString)") { [self] in
      let podcastEpisode = try await getOrCreatePodcastEpisode()
      try await queue.unshift(podcastEpisode.episode.id)
    }
  }

  func appendToQueue() {
    guard !atBottomOfQueue else { return }

    runTask("appendToQueue: \(state.toString)") { [self] in
      let podcastEpisode = try await getOrCreatePodcastEpisode()
      try await queue.append(podcastEpisode.episode.id)
    }
  }

  func removeFromQueue() {
    guard episode.queued else { return }

    runTask("removeFromQueue: \(state.toString)") { [self] in
      let podcastEpisode = try await getOrCreatePodcastEpisode()
      try await queue.dequeue(podcastEpisode.episode.id)
    }
  }

  func cacheEpisode() {
    runTask("cacheEpisode: \(state.toString)") { [self] in
      let podcastEpisode = try await getOrCreatePodcastEpisode()
      try await cacheManager.downloadToCache(for: podcastEpisode.id)
    }
  }

  func uncacheEpisode() {
    guard canClearCache else { return }

    runTask("uncacheEpisode: \(state.toString)") { [self] in
      let podcastEpisode = try await getOrCreatePodcastEpisode()
      try await repo.updateSaveInCache(podcastEpisode.id, saveInCache: false)
      try await cacheManager.clearCache(for: podcastEpisode.id)
    }
  }

  func saveEpisodeInCache() {
    runTask("saveEpisodeInCache: \(state.toString)") { [self] in
      let podcastEpisode = try await getOrCreatePodcastEpisode()
      try await repo.updateSaveInCache(podcastEpisode.id, saveInCache: true)
      try await cacheManager.downloadToCache(for: podcastEpisode.id)
    }
  }

  func markFinished() {
    guard !episode.finished else { return }

    runTask("markFinished: \(state.toString)") { [self] in
      let podcastEpisode = try await getOrCreatePodcastEpisode()
      try await repo.markFinished(podcastEpisode.id)
    }
  }

  func rate(_ rating: EpisodeRating?) {
    guard episode.rating != rating else { return }

    runTask("rate: \(state.toString)") { [self] in
      let podcastEpisode = try await getOrCreatePodcastEpisode()
      try await repo.updateRating(podcastEpisode.id, rating: rating)
    }
  }

  func showPodcast() {
    runTask("showPodcast: \(state.toString)") { [self] in
      let podcastEpisode = try await getOrCreatePodcastEpisode()
      navigation.showPodcast(podcastEpisode.podcast)
    }
  }

  // MARK: - Tag Management

  func addTag(_ tagID: Tag.ID) {
    guard let episodeID = episode.episodeID else {
      Self.log.warning("Cannot add tag to unsaved episode")
      return
    }

    runTask("addTag: \(tagID) to episode \(episodeID)") { [self] in
      try await repo.addTag(tagID, to: episodeID)
    }
  }

  func removeTag(_ tagID: Tag.ID) {
    guard let episodeID = episode.episodeID else {
      Self.log.warning("Cannot remove tag from unsaved episode")
      return
    }

    runTask("removeTag: \(tagID) from episode \(episodeID)") { [self] in
      try await repo.removeTag(tagID, from: episodeID)
    }
  }

  // MARK: - Observation Management

  @ObservationIgnored var observationTask: Task<Void, Never>?

  private func startObservation(_ podcastEpisode: PodcastEpisode) {
    if let observationTask, !observationTask.isCancelled {
      Self.log.debug("Observation already active; not starting observation")
      return
    }

    observationTask = Task { [weak self] in
      guard let self else { return }
      await observePodcastEpisode(podcastEpisode)
    }
  }

  private func observePodcastEpisode(_ podcastEpisode: PodcastEpisode) async {
    Self.log.debug("Starting observation for episode: \(podcastEpisode.toString)")

    // Clear our reference on any natural exit (deletion, error, normal end).
    // Skip when we were cancelled — disappear() or a re-binding
    // startObservation() has already cleared/replaced observationTask, and
    // stomping it would kill a newer task.
    defer {
      if !Task.isCancelled {
        observationTask = nil
      }
    }

    do {
      for try await updated in observatory.podcastEpisodeWithTags(podcastEpisode.id) {
        try Task.checkCancellation()

        Self.log.debug(
          "Updating observed episode: \(String(describing: updated?.podcastEpisode.toString))"
        )

        guard let updated
        else {
          Self.log.debug("Episode was deleted")
          // Post-deletion strategy: synthesize an `UnsavedPodcastEpisode`
          // from the just-cached `PodcastEpisode` we were observing. This
          // diverges from `PodcastDetailViewModel`, which re-parses the
          // feed via `loadPresentationFromFeed()`: podcasts have a per-feed
          // RSS endpoint we can fall back to, but episodes don't — the
          // cached row is the only thing available locally. The trade-off
          // is instant fallback at the cost of potentially-stale fields
          // until the next observation cycle.
          let deletedAsUnsaved: UnsavedPodcastEpisode
          do {
            deletedAsUnsaved = try podcastEpisode.toOriginalUnsavedPodcastEpisode()
          } catch {
            Self.log.caughtError(
              "observePodcastEpisode: failed to convert deleted episode back to unsaved",
              error
            )
            return
          }
          tags = []
          // Wipe the stale saved score before transition() queues the
          // unsaved-side refetch.
          score = nil
          transition(to: .unsaved(deletedAsUnsaved))
          return
        }

        if tags != updated.tags {
          tags = updated.tags
        }

        guard updated.podcastEpisode != state.savedPodcastEpisode
        else {
          Self.log.debug("Observed episode unchanged; skipping transition")
          continue
        }

        transition(to: .saved(updated.podcastEpisode))
      }
    } catch {
      Self.log.caughtError(
        "observePodcastEpisode: observation failed for \(podcastEpisode.toString)",
        error
      )
    }
  }

  // MARK: - Recommendation Observation

  @ObservationIgnored private var recommendationTask: Task<Void, Never>?

  // Skips a CoreML inference on every contextRevision tick after the first.
  // Cleared in scheduleRecommendationRefresh because every refresh trigger
  // is a kind change that may bring a different `.unsaved` payload (e.g.
  // post-deletion synthesis).
  @ObservationIgnored private var unsavedEmbeddingCache: (revision: Int, vector: [Float])?

  // Re-fetches this episode's score whenever the engine bumps
  // `contextRevision`, i.e. every time its scoring cache rebuilds. The
  // `.initial` schedule covers the "cache is already hot when the view
  // opens" case (the stream's `.dropFirst()` then skips Broadcast's replay
  // emit so we don't double-fire); cold caches yield nil and the section
  // stays hidden until the engine warms up.
  private func startRecommendationObservation() {
    if let recommendationTask, !recommendationTask.isCancelled {
      Self.log.debug("Recommendation observation already active; not starting again")
      return
    }

    scheduleRecommendationRefresh(reason: .initial)
    recommendationTask = Task(priority: taskPriority(.utility)) { [weak self] in
      guard let self else { return }

      for await _ in recommendationEngine.$contextRevision.stream().dropFirst() {
        guard !Task.isCancelled else { return }
        scheduleRecommendationRefresh(reason: .contextRevision)
      }
    }
  }

  private func fetchRecommendation() async {
    // Snapshot at entry — if a state-kind change races the scoring await,
    // the kind guard below drops the stale write before it overwrites the
    // fresh path's score.
    let entryState = state
    let newScore: EpisodeDetailDisplayedScore?
    switch entryState {
    case .initial:
      newScore = nil
    case .saved(let podcastEpisode):
      newScore = await scoreSavedEpisode(podcastEpisode)
    case .unsaved(let unsavedPodcastEpisode):
      newScore = await scoreUnsavedEpisode(unsavedPodcastEpisode)
    }
    guard entryState.kind == state.kind else {
      Self.log.debug(
        """
        fetchRecommendation: state kind changed during scoring; \
        dropping stale write
        """
      )
      return
    }
    score = newScore
  }

  private func scoreSavedEpisode(
    _ podcastEpisode: PodcastEpisode
  ) async -> EpisodeDetailDisplayedScore? {
    do {
      guard try await recommendationRepo.embedding(for: podcastEpisode.id) != nil else {
        return .embeddingPending
      }
      guard let score = try await recommendationEngine.recommendation(for: podcastEpisode.id)
      else { return nil }
      return .recommendation(score)
    } catch {
      Self.log.caughtError(
        "fetchRecommendation: saved scorer failed for \(podcastEpisode.toString)",
        error
      )
      return nil
    }
  }

  private func scoreUnsavedEpisode(
    _ unsavedPodcastEpisode: UnsavedPodcastEpisode
  ) async -> EpisodeDetailDisplayedScore? {
    contextualEmbedding.loadAssetsIfAvailable()
    guard contextualEmbedding.isAvailable else { return nil }

    let revision = contextualEmbedding.revision
    let vector: [Float]
    if let cached = unsavedEmbeddingCache, cached.revision == revision {
      vector = cached.vector
    } else {
      do {
        vector = try await EmbeddingService.embeddingVector(
          for: unsavedPodcastEpisode,
          embedding: contextualEmbedding
        )
      } catch {
        Self.log.caughtError(
          """
          fetchRecommendation: unsaved embedding failed for \
          \(unsavedPodcastEpisode.toString)
          """,
          error
        )
        return nil
      }
      unsavedEmbeddingCache = (revision: revision, vector: vector)
    }
    guard let value = recommendationEngine.similarityScore(forEmbedding: vector) else {
      return nil
    }
    return .similarity(value)
  }

  // Cancel-and-replace task per kind change / bootstrap so a brand-new
  // payload (e.g. post-deletion `.unsaved` synthesis) doesn't wait on a
  // parked saved-side fetch. Context-revision bursts coalesce through the
  // debounce instead — they're high-volume and don't change the payload's
  // identity, so the in-flight pass's kind guard already drops stale
  // writes without needing to cancel.
  @ObservationIgnored private var recommendationFetchTask: Task<Void, Never>?
  @ObservationIgnored private let recommendationDebounce = Debounce(
    duration: .milliseconds(150),
    priority: .utility
  )

  private enum EpisodeRecommendationRefreshReason {
    case initial
    case contextRevision
    case kindChanged
  }

  private func scheduleRecommendationRefresh(
    reason: EpisodeRecommendationRefreshReason
  ) {
    if case .kindChanged = reason { unsavedEmbeddingCache = nil }
    switch reason {
    case .initial, .kindChanged:
      recommendationFetchTask?.cancel()
      recommendationFetchTask = Task(priority: taskPriority(.utility)) { [weak self] in
        await self?.fetchRecommendation()
      }
    case .contextRevision:
      recommendationDebounce { [weak self] in
        await self?.fetchRecommendation()
      }
    }
  }

  private func clearRecommendationTasks() {
    recommendationTask?.cancel()
    recommendationTask = nil
    recommendationFetchTask?.cancel()
    recommendationFetchTask = nil
    recommendationDebounce.cancel()
  }

  // MARK: - Disappear

  func disappear() {
    Self.log.debug("disappear: executing")
    clearObservationTask()
    clearRecommendationTasks()
  }

  // MARK: - Private Helpers

  private func transition(to newState: EpisodeDetailState) {
    guard newState != state else { return }
    let recommendationKindChanged = state.kind != newState.kind
    logStateTransition(to: newState)
    state = newState
    if recommendationKindChanged {
      scheduleRecommendationRefresh(reason: .kindChanged)
    }
  }

  private func loadAndPlay(_ podcastEpisode: PodcastEpisode, seekTo seconds: Int) async throws {
    try await playManager.load(podcastEpisode)
    await playManager.seek(to: CMTime.seconds(Double(seconds)))
    await playManager.play()
  }

  private func getOrCreatePodcastEpisode() async throws -> PodcastEpisode {
    let podcastEpisode: PodcastEpisode
    switch state {
    case .saved(let saved):
      return saved
    case .unsaved(let unsavedPodcastEpisode):
      podcastEpisode = try await repo.upsertPodcastEpisode(unsavedPodcastEpisode)
    case .initial(let listedEpisode):
      podcastEpisode = try await listedEpisode.getOrCreatePodcastEpisode()
    }
    transition(to: .saved(podcastEpisode))
    startObservation(podcastEpisode)
    startRecommendationObservation()
    return podcastEpisode
  }

  // MARK: - Preview Helpers

  #if DEBUG
  // Preview-only seed; production goes through startRecommendationObservation.
  func previewSeedDisplayedScore(_ value: EpisodeDetailDisplayedScore?) {
    score = value
  }
  #endif
}
