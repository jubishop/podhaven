// Copyright Justin Bishop, 2026

import AVFoundation
import FactoryKit
import Foundation
import GRDB
import IdentifiedCollections
import Logging
import SwiftUI
import Tagged

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

  // MARK: - Data

  private let originTab: Navigation.Tab
  private let seed: EpisodeDetailSeed
  private let unsavedFallback: UnsavedPodcastEpisode?
  var episode: DisplayedEpisode
  var tags: IdentifiedArrayOf<Tag> = []
  private var recommendationScore: RecommendationScore?
  private var _podcastEpisode: PodcastEpisode?
  private var podcastEpisode: PodcastEpisode? {
    get { _podcastEpisode }
    set {
      guard let newValue
      else { Assert.fatal("Setting podcastEpisode to nil is not allowed") }

      Self.log.debug("Setting podcastEpisode to: \(newValue.toString)")

      _podcastEpisode = newValue
      episode = DisplayedEpisode(newValue)
    }
  }

  // MARK: - Derived State

  var onDeck: Bool {
    guard let podcastEpisode = podcastEpisode else { return false }
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
    guard let podcastEpisode = podcastEpisode else { return false }
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

  private init(seed: EpisodeDetailSeed, startTime: Int? = nil) {
    self.originTab = Container.shared.navigation().currentTab
    self.seed = seed
    self.episode = seed.initialEpisode
    self.unsavedFallback = Self.unsavedFallback(for: seed)
    self.startTime = startTime
  }

  convenience init(episode: DisplayedEpisode, startTime: Int? = nil) {
    self.init(seed: .displayedEpisode(episode), startTime: startTime)
  }

  convenience init(listedEpisode: ListedEpisode) {
    self.init(seed: .listedEpisode(listedEpisode))
  }

  private static func unsavedFallback(for seed: EpisodeDetailSeed) -> UnsavedPodcastEpisode? {
    let unsavedSource: UnsavedPodcastEpisode?
    switch seed {
    case .displayedEpisode(let episode):
      unsavedSource = episode.source.unsaved
    case .listedEpisode(let listedEpisode):
      unsavedSource = listedEpisode.unsavedPodcastEpisode
    }

    guard let unsavedSource else { return nil }

    do {
      return try unsavedSource.toOriginalUnsavedPodcastEpisode()
    } catch {
      Assert.fatal(
        """
        Cannot build UnsavedPodcastEpisode fallback \
        for episode: \(unsavedSource.toString). \
        Error: \(error)
        """
      )
    }
  }

  func appear() {
    Task { [weak self] in
      guard let self else { return }

      do {
        try await performAppear()
      } catch {
        Self.log.caughtError("appear: failed for \(episode.toString)", error)
        guard ErrorKit.isRemarkable(error) else { return }
        alert(ErrorKit.message(for: error))
      }
    }
  }

  func performAppear() async throws {
    let podcastEpisode = try await repo.podcastEpisode(episode.mediaGUID)

    if let podcastEpisode {
      Self.log.debug("Podcast episode: \(podcastEpisode.toString) exists in db")

      self.podcastEpisode = podcastEpisode
      startObservation()
      startRecommendationObservation()
    } else {
      Self.log.debug("Podcast episode: \(episode.toString) does not exist in db")

      _podcastEpisode = nil
      guard let unsavedFallback else {
        Self.log.warning("Episode no longer exists for detail hydration: \(episode.toString)")
        alert("This episode is no longer available.")
        navigation.dismiss(from: originTab)
        return
      }
      episode = DisplayedEpisode(unsavedFallback)
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
        Self.log.caughtError("playNow: failed to get/create episode \(episode.toString)", error)
        guard ErrorKit.isRemarkable(error) else { return }
        alert(ErrorKit.message(for: error))
        return
      }

      do {
        try await playManager.load(podcastEpisode)
        await playManager.play()
      } catch {
        Self.log.caughtError("playNow: failed to load episode \(episode.toString)", error)
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
          "playAt: failed for \(episode.toString) at timestamp \(timestamp)",
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
        Self.log.caughtError("addToTopOfQueue: failed for \(episode.toString)", error)
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
        Self.log.caughtError("appendToQueue: failed for \(episode.toString)", error)
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
        Self.log.caughtError("removeFromQueue: failed for \(episode.toString)", error)
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
        Self.log.caughtError("cacheEpisode: failed for \(episode.toString)", error)
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
          "uncacheEpisode: failed to get/create episode \(episode.toString)",
          error
        )
        guard ErrorKit.isRemarkable(error) else { return }
        alert(ErrorKit.message(for: error))
        return
      }

      do {
        try await repo.updateSaveInCache(podcastEpisode.id, saveInCache: false)
      } catch {
        Self.log.caughtError("uncacheEpisode: failed to unsave episode \(episode.toString)", error)
        guard ErrorKit.isRemarkable(error) else { return }
        alert(ErrorKit.message(for: error))
      }

      do {
        try await cacheManager.clearCache(for: podcastEpisode.id)
      } catch {
        Self.log.caughtError(
          "uncacheEpisode: failed to clear cache for \(episode.toString)",
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
          "saveEpisodeInCache: failed to get/create episode \(episode.toString)",
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
          "saveEpisodeInCache: failed to save episode \(episode.toString)",
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
          "saveEpisodeInCache: failed to cache episode \(episode.toString)",
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
        Self.log.caughtError("markFinished: failed for \(episode.toString)", error)
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
        Self.log.caughtError("rate: failed for \(episode.toString)", error)
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
        Self.log.caughtError("showPodcast: failed for \(episode.toString)", error)
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
    guard let podcastEpisode = self.podcastEpisode
    else { Assert.fatal("Observing a non-saved podcastEpisode") }

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
          let deletedPresentation = DisplayedEpisode(
            try podcastEpisode.toOriginalUnsavedPodcastEpisode()
          )
          tags = []
          clearRecommendationTask()
          recommendationScore = nil
          _podcastEpisode = nil
          episode = deletedPresentation
          return
        }

        if updated.podcastEpisode != self.podcastEpisode {
          self.podcastEpisode = updated.podcastEpisode
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
    guard let podcastEpisode = self.podcastEpisode else { return }

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

  private func loadAndPlay(_ podcastEpisode: PodcastEpisode, seekTo seconds: Int) async throws {
    try await playManager.load(podcastEpisode)
    await playManager.seek(to: CMTime.seconds(Double(seconds)))
    await playManager.play()
  }

  private func getOrCreatePodcastEpisode() async throws -> PodcastEpisode {
    if let podcastEpisode = self.podcastEpisode { return podcastEpisode }

    let podcastEpisode: PodcastEpisode
    switch seed {
    case .listedEpisode(let listedEpisode):
      podcastEpisode = try await listedEpisode.getOrCreatePodcastEpisode()
    case .displayedEpisode:
      podcastEpisode = try await episode.getOrCreatePodcastEpisode()
    }
    self.podcastEpisode = podcastEpisode
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
