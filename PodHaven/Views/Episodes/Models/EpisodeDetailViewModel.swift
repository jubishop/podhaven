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
enum EpisodeDetailState: Sendable {
  case initial(ListedEpisode)
  case unsaved(UnsavedPodcastEpisode)
  case saved(PodcastEpisode)

  var savedPodcastEpisode: PodcastEpisode? {
    guard case .saved(let podcastEpisode) = self else { return nil }
    return podcastEpisode
  }

  var detailContent: EpisodeDetailContent {
    switch self {
    case .initial(let listed): return .initial(listed)
    case .unsaved(let unsaved): return .loaded(DisplayedEpisode(unsaved))
    case .saved(let podcastEpisode): return .loaded(DisplayedEpisode(podcastEpisode))
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

@Observable @MainActor class EpisodeDetailViewModel {
  @ObservationIgnored @DynamicInjected(\.alert) private var alert
  @ObservationIgnored @DynamicInjected(\.cacheManager) private var cacheManager

  @ObservationIgnored @DynamicInjected(\.navigation) private var navigation
  @ObservationIgnored @DynamicInjected(\.observatory) private var observatory
  @ObservationIgnored @DynamicInjected(\.playManager) private var playManager
  @ObservationIgnored @DynamicInjected(\.queue) private var queue
  @ObservationIgnored @DynamicInjected(\.recommendationEngine) private var recommendationEngine
  @ObservationIgnored @DynamicInjected(\.repo) private var repo
  @ObservationIgnored @DynamicInjected(\.sharedState) private var sharedState

  private static let log = Log.as(LogSubsystem.EpisodesView.detail)

  // MARK: - State

  private let originTab: Navigation.Tab
  private(set) var state: EpisodeDetailState
  var tags: IdentifiedArrayOf<Tag> = []
  private var recommendationScore: RecommendationScore?

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
  var displayedRecommendationScore: RecommendationScore? {
    guard episode.rating == nil, !episode.finished else { return nil }
    return recommendationScore
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
    if let unsavedPodcastEpisode = listedEpisode.unsavedPodcastEpisode {
      // Both `.listedEpisode(.unsaved(...))` and `.displayedEpisode(.unsaved(...))`
      // collapse to `.unsaved(UnsavedPodcastEpisode)` here. Round-trip through
      // `toOriginalUnsavedPodcastEpisode` to drop any saved-only fields that
      // may have leaked into the listing snapshot. URL validation is
      // idempotent for already-constructed unsaved values, so the throw
      // path should be unreachable; if it ever does fire, log and seed the
      // state with the un-stripped value rather than crashing.
      let resolved: UnsavedPodcastEpisode
      do {
        resolved = try unsavedPodcastEpisode.toOriginalUnsavedPodcastEpisode()
      } catch {
        Self.log.caughtError(
          """
          init(listedEpisode:): failed to strip saved-only fields for \
          \(unsavedPodcastEpisode.toString)
          """,
          error
        )
        resolved = unsavedPodcastEpisode
      }
      self.init(state: .unsaved(resolved))
    } else {
      self.init(state: .initial(listedEpisode))
    }
  }

  func appear() {
    Task { [weak self] in
      guard let self else { return }

      do {
        try await performAppear()
      } catch {
        Self.log.caughtError("appear: failed for \(state.toString)", error)
        guard ErrorKit.isRemarkable(error) else { return }
        alert(ErrorKit.message(for: error))
      }
    }
  }

  func performAppear() async throws {
    let podcastEpisode = try await repo.podcastEpisode(state.mediaGUID)

    if let podcastEpisode {
      Self.log.debug("Podcast episode: \(podcastEpisode.toString) exists in db")

      transition(to: .saved(podcastEpisode))
      startObservation()
      startRecommendationObservation()
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

    if let startTime {
      Self.log.debug("Auto-playing from startTime: \(startTime)s")
      let podcastEpisode = try await getOrCreatePodcastEpisode()
      try await loadAndPlay(podcastEpisode, seekTo: startTime)
    }
  }

  // MARK: - Public Methods

  func playNow() {
    Task { [weak self] in
      guard let self else { return }

      let podcastEpisode: PodcastEpisode
      do {
        podcastEpisode = try await getOrCreatePodcastEpisode()
      } catch {
        Self.log.caughtError("playNow: failed to get/create episode \(state.toString)", error)
        guard ErrorKit.isRemarkable(error) else { return }
        alert(ErrorKit.message(for: error))
        return
      }

      do {
        try await playManager.load(podcastEpisode)
        await playManager.play()
      } catch {
        Self.log.caughtError("playNow: failed to load episode \(state.toString)", error)
        guard ErrorKit.isRemarkable(error) else { return }
        alert(ErrorKit.message(for: error))
      }
    }
  }

  func playAt(timestamp: String) {
    guard let seconds = Timestamp.parse(timestamp) else {
      Self.log.warning("Failed to parse timestamp: \(timestamp)")
      return
    }

    Task { [weak self] in
      guard let self else { return }

      do {
        let podcastEpisode = try await getOrCreatePodcastEpisode()
        try await loadAndPlay(podcastEpisode, seekTo: seconds)
      } catch {
        Self.log.caughtError(
          "playAt: failed for \(state.toString) at timestamp \(timestamp)",
          error
        )
        guard ErrorKit.isRemarkable(error) else { return }
        alert(ErrorKit.message(for: error))
      }
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

    Task { [weak self] in
      guard let self else { return }

      do {
        let podcastEpisode = try await getOrCreatePodcastEpisode()
        try await queue.unshift(podcastEpisode.episode.id)
      } catch {
        Self.log.caughtError("addToTopOfQueue: failed for \(state.toString)", error)
        guard ErrorKit.isRemarkable(error) else { return }
        alert(ErrorKit.message(for: error))
      }
    }
  }

  func appendToQueue() {
    guard !atBottomOfQueue else { return }

    Task { [weak self] in
      guard let self else { return }

      do {
        let podcastEpisode = try await getOrCreatePodcastEpisode()
        try await queue.append(podcastEpisode.episode.id)
      } catch {
        Self.log.caughtError("appendToQueue: failed for \(state.toString)", error)
        guard ErrorKit.isRemarkable(error) else { return }
        alert(ErrorKit.message(for: error))
      }
    }
  }

  func removeFromQueue() {
    guard episode.queued else { return }

    Task { [weak self] in
      guard let self else { return }

      do {
        let podcastEpisode = try await getOrCreatePodcastEpisode()
        try await queue.dequeue(podcastEpisode.episode.id)
      } catch {
        Self.log.caughtError("removeFromQueue: failed for \(state.toString)", error)
        guard ErrorKit.isRemarkable(error) else { return }
        alert(ErrorKit.message(for: error))
      }
    }
  }

  func cacheEpisode() {
    Task { [weak self] in
      guard let self else { return }

      do {
        let podcastEpisode = try await getOrCreatePodcastEpisode()
        try await cacheManager.downloadToCache(for: podcastEpisode.id)
      } catch {
        Self.log.caughtError("cacheEpisode: failed for \(state.toString)", error)
        guard ErrorKit.isRemarkable(error) else { return }
        alert(ErrorKit.message(for: error))
      }
    }
  }

  func uncacheEpisode() {
    guard canClearCache else { return }

    Task { [weak self] in
      guard let self else { return }

      let podcastEpisode: PodcastEpisode
      do {
        podcastEpisode = try await getOrCreatePodcastEpisode()
      } catch {
        Self.log.caughtError(
          "uncacheEpisode: failed to get/create episode \(state.toString)",
          error
        )
        guard ErrorKit.isRemarkable(error) else { return }
        alert(ErrorKit.message(for: error))
        return
      }

      do {
        try await repo.updateSaveInCache(podcastEpisode.id, saveInCache: false)
      } catch {
        Self.log.caughtError("uncacheEpisode: failed to unsave episode \(state.toString)", error)
        guard ErrorKit.isRemarkable(error) else { return }
        alert(ErrorKit.message(for: error))
      }

      do {
        try await cacheManager.clearCache(for: podcastEpisode.id)
      } catch {
        Self.log.caughtError(
          "uncacheEpisode: failed to clear cache for \(state.toString)",
          error
        )
        guard ErrorKit.isRemarkable(error) else { return }
        alert(ErrorKit.message(for: error))
      }
    }
  }

  func saveEpisodeInCache() {
    Task { [weak self] in
      guard let self else { return }

      let podcastEpisode: PodcastEpisode
      do {
        podcastEpisode = try await getOrCreatePodcastEpisode()
      } catch {
        Self.log.caughtError(
          "saveEpisodeInCache: failed to get/create episode \(state.toString)",
          error
        )
        guard ErrorKit.isRemarkable(error) else { return }
        alert(ErrorKit.message(for: error))
        return
      }

      do {
        try await repo.updateSaveInCache(podcastEpisode.id, saveInCache: true)
      } catch {
        Self.log.caughtError(
          "saveEpisodeInCache: failed to save episode \(state.toString)",
          error
        )
        guard ErrorKit.isRemarkable(error) else { return }
        alert(ErrorKit.message(for: error))
        return
      }

      do {
        try await cacheManager.downloadToCache(for: podcastEpisode.id)
      } catch {
        Self.log.caughtError(
          "saveEpisodeInCache: failed to cache episode \(state.toString)",
          error
        )
        guard ErrorKit.isRemarkable(error) else { return }
        alert(ErrorKit.message(for: error))
      }
    }
  }

  func markFinished() {
    guard !episode.finished else { return }

    Task { [weak self] in
      guard let self else { return }

      do {
        let podcastEpisode = try await getOrCreatePodcastEpisode()
        try await repo.markFinished(podcastEpisode.id)
      } catch {
        Self.log.caughtError("markFinished: failed for \(state.toString)", error)
        guard ErrorKit.isRemarkable(error) else { return }
        alert(ErrorKit.message(for: error))
      }
    }
  }

  func rate(_ rating: EpisodeRating?) {
    guard episode.rating != rating else { return }

    Task { [weak self] in
      guard let self else { return }

      do {
        let podcastEpisode = try await getOrCreatePodcastEpisode()
        try await repo.updateRating(podcastEpisode.id, rating: rating)
      } catch {
        Self.log.caughtError("rate: failed for \(state.toString)", error)
        guard ErrorKit.isRemarkable(error) else { return }
        alert(ErrorKit.message(for: error))
      }
    }
  }

  func showPodcast() {
    Task { [weak self] in
      guard let self else { return }

      do {
        let podcastEpisode = try await getOrCreatePodcastEpisode()
        navigation.showPodcast(podcastEpisode.podcast)
      } catch {
        Self.log.caughtError("showPodcast: failed for \(state.toString)", error)
        guard ErrorKit.isRemarkable(error) else { return }
        alert(ErrorKit.message(for: error))
      }
    }
  }

  // MARK: - Tag Management

  func addTag(_ tagID: Tag.ID) {
    guard let episodeID = episode.episodeID else {
      Self.log.warning("Cannot add tag to unsaved episode")
      return
    }

    Task { [weak self] in
      guard let self else { return }

      do {
        try await repo.addTag(tagID, to: episodeID)
      } catch {
        Self.log.caughtError("addTag: failed to add tag \(tagID) to episode \(episodeID)", error)
        guard ErrorKit.isRemarkable(error) else { return }
        alert(ErrorKit.message(for: error))
      }
    }
  }

  func removeTag(_ tagID: Tag.ID) {
    guard let episodeID = episode.episodeID else {
      Self.log.warning("Cannot remove tag from unsaved episode")
      return
    }

    Task { [weak self] in
      guard let self else { return }

      do {
        try await repo.removeTag(tagID, from: episodeID)
      } catch {
        Self.log.caughtError(
          "removeTag: failed to remove tag \(tagID) from episode \(episodeID)",
          error
        )
        guard ErrorKit.isRemarkable(error) else { return }
        alert(ErrorKit.message(for: error))
      }
    }
  }

  // MARK: - Observation Management

  @ObservationIgnored private var observationTask: Task<Void, Never>?

  private func startObservation() {
    guard let podcastEpisode = state.savedPodcastEpisode else {
      Self.log.warning("startObservation: skipped, state is \(state.toString)")
      return
    }

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
          clearRecommendationTask()
          recommendationScore = nil
          transition(to: .unsaved(deletedAsUnsaved))
          return
        }

        if updated.podcastEpisode != state.savedPodcastEpisode {
          transition(to: .saved(updated.podcastEpisode))
        }
        if tags != updated.tags {
          tags = updated.tags
        }
      }
    } catch {
      Self.log.caughtError(
        "observePodcastEpisode: observation failed for \(podcastEpisode.toString)",
        error
      )
    }
  }

  private func clearObservationTask() {
    observationTask?.cancel()
    observationTask = nil
  }

  // MARK: - Recommendation Observation

  @ObservationIgnored private var recommendationTask: Task<Void, Never>?

  // Re-fetches this episode's score whenever the engine bumps
  // `contextRevision`, i.e. every time its scoring cache rebuilds. The
  // bootstrap emit covers the "cache is already hot when the view opens"
  // case; cold caches yield nil and the section stays hidden until the
  // engine warms up.
  private func startRecommendationObservation() {
    if let recommendationTask, !recommendationTask.isCancelled {
      Self.log.debug("Recommendation observation already active; not starting again")
      return
    }

    recommendationTask = Task { [weak self] in
      guard let self else { return }

      for await _ in recommendationEngine.$contextRevision.stream() {
        guard !Task.isCancelled else { return }
        await fetchRecommendation()
      }
    }
  }

  private func fetchRecommendation() async {
    guard let podcastEpisode = state.savedPodcastEpisode else { return }

    do {
      recommendationScore = try await recommendationEngine.recommendation(
        for: podcastEpisode.id
      )
    } catch {
      Self.log.caughtError(
        "fetchRecommendation: failed for \(podcastEpisode.toString)",
        error
      )
    }
  }

  private func clearRecommendationTask() {
    recommendationTask?.cancel()
    recommendationTask = nil
  }

  // MARK: - Disappear

  func disappear() {
    Self.log.debug("disappear: executing")
    clearObservationTask()
    clearRecommendationTask()
  }

  // MARK: - Private Helpers

  private func transition(to newState: EpisodeDetailState) {
    Self.log.debug("transitioning state \(state.toString) → \(newState.toString)")
    state = newState
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
    startObservation()
    startRecommendationObservation()
    return podcastEpisode
  }

  // MARK: - Preview Helpers

  #if DEBUG
  // Preview-only seed; production code drives `recommendationScore`
  // exclusively through `startRecommendationObservation`.
  func previewSeedRecommendationScore(_ score: RecommendationScore?) {
    recommendationScore = score
  }
  #endif
}
