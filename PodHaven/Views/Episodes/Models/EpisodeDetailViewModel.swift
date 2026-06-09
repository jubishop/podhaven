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
}

enum EpisodeDetailDisplayedScore: Sendable {
  case recommendation(RecommendationScore)
  case similarity(Float)
  case pending
}

@Observable @MainActor class EpisodeDetailViewModel {
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

  private static let log = Log.as(LogSubsystem.EpisodesView.detail)

  // MARK: - State

  private let originTab: Navigation.Tab
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

  // `similarityScore` seeds the displayed score with a value the presenting
  // list already computed, so the section renders immediately; the scoring
  // coordinator's first pass then confirms or replaces it.
  convenience init(listedEpisode: ListedEpisode, similarityScore: Float? = nil) {
    if let unsavedPodcastEpisode = listedEpisode.unsaved {
      self.init(state: .unsaved(unsavedPodcastEpisode))
      if let similarityScore {
        score = .similarity(similarityScore)
      }
    } else {
      self.init(state: .initial(listedEpisode))
    }
  }

  // MARK: - Lifecycle

  @ObservationIgnored @DynamicInjected(\.alert) private var alert
  private(set) var state: EpisodeDetailState

  @ObservationIgnored private let lifecycle = DetailLifecycle()

  func appear() {
    if lifecycle.appear(performAppear: { [weak self] in try await self?.performAppear() }) {
      recommendationCoordinator.cancel()
    }
  }

  func disappear() {
    lifecycle.disappear()
    recommendationCoordinator.cancel()
  }

  private func performAppear() async throws {
    let podcastEpisode: PodcastEpisode?
    switch state {
    case .saved(let saved):
      podcastEpisode = try await repo.podcastEpisode(saved.id)
    case .initial(let listed):
      // `.initial` only holds saved list rows — unsaved rows route to
      // `.unsaved` at init — so its Episode.ID is always present. Resolve by it
      // so a (guid, mediaURL) shared across podcasts can't bind to another's row.
      guard let episodeID = listed.episodeID else {
        Assert.fatal("`.initial` detail seed missing Episode.ID: \(listed.toString)")
      }
      podcastEpisode = try await repo.podcastEpisode(episodeID)
    case .unsaved(let unsaved):
      // Only treat as saved if this episode already exists under its own feed.
      podcastEpisode = try await repo.podcastEpisode(
        unsaved.mediaGUID,
        feedURL: unsaved.feedURL
      )
    }
    try Task.checkCancellation()

    if let podcastEpisode {
      Self.log.debug("Podcast episode: \(podcastEpisode.toString) exists in db")

      transition(to: .saved(podcastEpisode))
      try Task.checkCancellation()
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

    try Task.checkCancellation()
    startRecommendationObservation()

    if let startTime {
      try Task.checkCancellation()
      Self.log.debug("Auto-playing from startTime: \(startTime)s")
      let podcastEpisode = try await getOrCreatePodcastEpisode()
      try Task.checkCancellation()
      try await loadAndPlay(podcastEpisode, seekTo: startTime)
    }
  }

  // MARK: - Public Methods

  func playNow() {
    lifecycle.runTask("playNow: \(state.toString)") { [weak self] in
      guard let self else { return }
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

    lifecycle.runTask("playAt: \(state.toString) at timestamp \(timestamp)") { [weak self] in
      guard let self else { return }
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

    lifecycle.runTask("addToTopOfQueue: \(state.toString)") { [weak self] in
      guard let self else { return }
      let podcastEpisode = try await getOrCreatePodcastEpisode()
      try await queue.unshift(podcastEpisode.episode.id)
    }
  }

  func appendToQueue() {
    guard !atBottomOfQueue else { return }

    lifecycle.runTask("appendToQueue: \(state.toString)") { [weak self] in
      guard let self else { return }
      let podcastEpisode = try await getOrCreatePodcastEpisode()
      try await queue.append(podcastEpisode.episode.id)
    }
  }

  func removeFromQueue() {
    guard episode.queued else { return }

    lifecycle.runTask("removeFromQueue: \(state.toString)") { [weak self] in
      guard let self else { return }
      let podcastEpisode = try await getOrCreatePodcastEpisode()
      try await queue.dequeue(podcastEpisode.episode.id)
    }
  }

  func cacheEpisode() {
    lifecycle.runTask("cacheEpisode: \(state.toString)") { [weak self] in
      guard let self else { return }
      let podcastEpisode = try await getOrCreatePodcastEpisode()
      try await cacheManager.downloadToCache(for: podcastEpisode.id)
    }
  }

  func uncacheEpisode() {
    guard canClearCache else { return }

    lifecycle.runTask("uncacheEpisode: \(state.toString)") { [weak self] in
      guard let self else { return }
      let podcastEpisode = try await getOrCreatePodcastEpisode()
      try await repo.updateSaveInCache(podcastEpisode.id, saveInCache: false)
      try await cacheManager.clearCache(for: podcastEpisode.id)
    }
  }

  func saveEpisodeInCache() {
    lifecycle.runTask("saveEpisodeInCache: \(state.toString)") { [weak self] in
      guard let self else { return }
      let podcastEpisode = try await getOrCreatePodcastEpisode()
      try await repo.updateSaveInCache(podcastEpisode.id, saveInCache: true)
      try await cacheManager.downloadToCache(for: podcastEpisode.id)
    }
  }

  func markFinished() {
    guard !episode.finished else { return }

    lifecycle.runTask("markFinished: \(state.toString)") { [weak self] in
      guard let self else { return }
      let podcastEpisode = try await getOrCreatePodcastEpisode()
      try await repo.markFinished(podcastEpisode.id)
    }
  }

  func rate(_ rating: EpisodeRating?) {
    guard episode.rating != rating else { return }

    lifecycle.runTask("rate: \(state.toString)") { [weak self] in
      guard let self else { return }
      let podcastEpisode = try await getOrCreatePodcastEpisode()
      try await repo.updateRating(podcastEpisode.id, rating: rating)
    }
  }

  func showPodcast() {
    lifecycle.runTask("showPodcast: \(state.toString)") { [weak self] in
      guard let self else { return }
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

    lifecycle.runTask("addTag: \(tagID) to episode \(episodeID)") { [weak self] in
      guard let self else { return }
      try await repo.addTag(tagID, to: episodeID)
    }
  }

  func removeTag(_ tagID: Tag.ID) {
    guard let episodeID = episode.episodeID else {
      Self.log.warning("Cannot remove tag from unsaved episode")
      return
    }

    lifecycle.runTask("removeTag: \(tagID) from episode \(episodeID)") { [weak self] in
      guard let self else { return }
      try await repo.removeTag(tagID, from: episodeID)
    }
  }

  // MARK: - Observation Management

  private func startObservation(_ podcastEpisode: PodcastEpisode) {
    guard lifecycle.isOnScreen else {
      Self.log.debug("startObservation: skipped off-screen")
      return
    }

    let started = lifecycle.startObservation { [weak self] in
      guard let self else { return }
      await observePodcastEpisode(podcastEpisode)
    }

    if !started {
      Self.log.debug("Observation already active; not starting observation")
    }
  }

  private func observePodcastEpisode(_ podcastEpisode: PodcastEpisode) async {
    Self.log.debug("Starting observation for episode: \(podcastEpisode.toString)")

    do {
      for try await updated in observatory.podcastEpisodeWithTags(podcastEpisode.id) {
        try Task.checkCancellation()
        guard lifecycle.isOnScreen else { return }

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

  @ObservationIgnored
  private let unsavedEpisodeEmbeddingScorer = UnsavedEpisodeEmbeddingScorer()

  private struct RecommendationScoringSnapshot: Equatable, Sendable {
    let scoringRevision: Int
    let state: State

    enum State: Equatable, Sendable {
      case unsaved(
        mediaGUID: MediaGUID,
        embeddingRevision: Int,
        embeddingSource: String
      )
      case saved(mediaGUID: MediaGUID, episodeID: Episode.ID)
    }
  }

  @ObservationIgnored
  private lazy var recommendationCoordinator = RecommendationScoringCoordinator<
    RecommendationScoringSnapshot, EpisodeDetailDisplayedScore?
  >(
    makeSnapshot: { [weak self] in
      guard let self else { return nil }
      return currentRecommendationScoringSnapshot()
    },
    score: { [weak self] in
      guard let self, let source = currentRecommendationSource()
      else { return .cancelled }
      do {
        let (result, cacheable) = try await computeRecommendation(source: source)
        return cacheable ? .cacheable(result) : .uncacheable(result)
      } catch is CancellationError {
        return .cancelled
      } catch {
        Self.log.caughtError("recommendation scoring failed", error)
        return .uncacheable(nil)
      }
    },
    apply: { [weak self] in
      guard let self else { return }
      score = $0
    },
    refreshOnAssetsLoaded: true
  )

  private func currentRecommendationScoringSnapshot() -> RecommendationScoringSnapshot? {
    guard let snapshotState = currentSnapshotState() else { return nil }
    return RecommendationScoringSnapshot(
      scoringRevision: recommendationEngine.scoringRevision,
      state: snapshotState
    )
  }

  private func currentSnapshotState() -> RecommendationScoringSnapshot.State? {
    switch state {
    case .initial:
      return nil
    case .unsaved(let unsaved):
      return .unsaved(
        mediaGUID: unsaved.mediaGUID,
        embeddingRevision: contextualEmbedding.revision,
        embeddingSource: unsaved.searchableString
      )
    case .saved(let podcastEpisode):
      return .saved(
        mediaGUID: podcastEpisode.mediaGUID,
        episodeID: podcastEpisode.id
      )
    }
  }

  private enum RecommendationSource {
    case unsaved(UnsavedPodcastEpisode)
    case saved(PodcastEpisode)
  }

  private func currentRecommendationSource() -> RecommendationSource? {
    switch state {
    case .initial: return nil
    case .unsaved(let unsavedPodcastEpisode): return .unsaved(unsavedPodcastEpisode)
    case .saved(let podcastEpisode): return .saved(podcastEpisode)
    }
  }

  private func startRecommendationObservation() {
    guard lifecycle.isOnScreen else {
      Self.log.debug("startRecommendationObservation: skipped off-screen")
      return
    }
    recommendationCoordinator.startObservations()
    recommendationCoordinator.refresh()
  }

  private func computeRecommendation(
    source: RecommendationSource
  ) async throws -> (EpisodeDetailDisplayedScore?, cacheable: Bool) {
    switch source {
    case .saved(let podcastEpisode):
      return (try await scoreSavedEpisode(podcastEpisode), true)
    case .unsaved(let unsavedPodcastEpisode):
      return try await scoreUnsavedEpisode(unsavedPodcastEpisode)
    }
  }

  private func scoreSavedEpisode(
    _ podcastEpisode: PodcastEpisode
  ) async throws -> EpisodeDetailDisplayedScore {
    guard try await recommendationRepo.embedding(for: podcastEpisode.id) != nil else {
      return .pending
    }
    // The embedding exists but the engine cache is still cold (too few
    // signals to build a scoring context): keep showing pending rather than
    // letting the section vanish.
    guard let score = try await recommendationEngine.recommendation(for: podcastEpisode.id)
    else { return .pending }
    return .recommendation(score)
  }

  private func scoreUnsavedEpisode(
    _ unsavedPodcastEpisode: UnsavedPodcastEpisode
  ) async throws -> (EpisodeDetailDisplayedScore?, cacheable: Bool) {
    let (score, cacheable) = try await unsavedEpisodeEmbeddingScorer.similarityScore(
      for: unsavedPodcastEpisode
    )
    guard cacheable else { return (nil, false) }
    guard let score else { return (nil, true) }
    return (.similarity(score), true)
  }

  // MARK: - Private Helpers

  private func transition(to newState: EpisodeDetailState) {
    guard newState != state else { return }
    Self.log.debug("transitioning state \(state.toString) → \(newState.toString)")
    state = newState
    guard lifecycle.isOnScreen else { return }
    recommendationCoordinator.refresh()
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
      podcastEpisode = try await unsavedPodcastEpisode.getOrCreatePodcastEpisodeSavingSeries()
    case .initial(let listedEpisode):
      podcastEpisode = try await listedEpisode.getOrCreatePodcastEpisode()
    }
    transition(to: .saved(podcastEpisode))
    guard lifecycle.isOnScreen else { return podcastEpisode }
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
