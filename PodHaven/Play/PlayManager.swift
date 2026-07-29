// Copyright Justin Bishop, 2025

import AVFoundation
import Combine
import FactoryKit
import Foundation
import GRDB
import IdentifiedCollections
import Logging
import Nuke
import SwiftUI
import Tagged

extension Container {
  var playManager: Factory<PlayManager> {
    Factory(self) { PlayManager() }.scope(.cached)
  }
}

@PlayActor
final class PlayManager {
  private enum LoadTransitionOutcome {
    case didNotLoad
    case failed(Episode.ID)
    case succeeded
  }

  private enum LoadTransitionState: Equatable {
    case preservingPlayback
    case ownsAudioSession
    case ownsPlaybackState
    case establishedPlayback(Episode.ID)
  }

  private final class LoadTransition {
    var establishedPlayback: (episodeID: Episode.ID, ownerID: UUID)?
    var id: UUID
    var state = LoadTransitionState.preservingPlayback
    var finishedIDs: Set<Episode.ID> = []
    init(id: UUID) { self.id = id }
  }

  private enum PendingPlaybackRequest {
    case none
    case play(Episode.ID)
  }

  @DynamicInjected(\.cacheManager) private var cacheManager
  @DynamicInjected(\.commandCenterStream) var commandCenterStream
  @DynamicInjected(\.fileManager) var fileManager
  @DynamicInjected(\.imagePipeline) private var imagePipeline
  @DynamicInjected(\.notifications) var notifications
  @DynamicInjected(\.queue) var queue
  @DynamicInjected(\.repo) var repo
  @DynamicInjected(\.sharedState) var sharedState
  @DynamicInjected(\.sleeper) private var sleeper
  @DynamicInjected(\.stateManager) private var stateManager
  @DynamicInjected(\.userSettings) var userSettings

  var alert: Alert { get async { await Container.shared.alert() } }
  var podAVPlayer: PodAVPlayer { get async { await Container.shared.podAVPlayer() } }
  private var settledOnDeckID: Episode.ID? {
    guard loadTransition == nil, case .none = pendingPlaybackRequest else { return nil }
    return sharedState.onDeck?.id
  }

  nonisolated static let log = Log.as(LogSubsystem.Play.manager)

  // MARK: - Configurable Constants

  let recoveryDebounceInterval: TimeInterval = 5
  private let remoteScrubSuppressionDuration: Duration = .seconds(1)
  // A remote scrub landing within this distance of the episode duration counts
  // as a scrub to the very end.
  let remoteScrubEndEpsilon: TimeInterval = 2
  // Below this playback position an episode counts as just-started, so a
  // scrub-to-end is almost certainly a stale gesture rather than intent.
  let remoteScrubJustStartedThreshold: TimeInterval = 3

  // MARK: - State Management

  var lastRecoveryAttempt: (episodeID: Episode.ID, time: Date)?
  private var imageFetchTask: Task<Void, Never>?
  private var loadTransition: LoadTransition?
  private(set) var loadTask: Task<Bool, any Error>?
  private let startOnce = AsyncOnce()
  private let startStreamConsumersOnce = Once()
  private(set) var ignoreRemoteScrubCommands = false
  private var restartScrubCommandsTask: Task<Void, any Error>?
  private(set) var onDeckBecameCurrentAt: Date?
  private var lastLoggedTime = Date.distantPast
  private var lastNowPlayingElapsedWrite: CMTime?
  private var lastBackgroundSnapshot: Date?
  private var pendingPlaybackRequest = PendingPlaybackRequest.none
  private var postPauseObservationTask: Task<Void, Never>?

  // MARK: - Initialization

  fileprivate nonisolated init() {}

  nonisolated func startStreamConsumers() {
    startStreamConsumersOnce.run {
      Self.log.debug("startStreamConsumers: executing")

      notificationTracking()
      asyncStreams()
    }
  }

  // Audio session and command handlers must already be configured.
  func start() async {
    await startOnce.run {
      Self.log.debug("start: executing")

      self.startStreamConsumers()
      await self.restorePersistedEpisodeIfNeeded()
    }
  }

  private func restorePersistedEpisodeIfNeeded() async {
    guard sharedState.onDeck == nil else { return }
    guard let currentEpisodeID = sharedState.currentEpisodeID else { return }

    Self.log.info("Loading persisted episode \(currentEpisodeID)")
    do {
      guard let podcastEpisode = try await repo.podcastEpisode(currentEpisodeID) else {
        Self.log.warning("Persisted episode \(currentEpisodeID) not found in database")
        stateManager.clearOnDeck()
        return
      }
      try await load(podcastEpisode)
    } catch {
      Self.log.caughtError(
        "restorePersistedEpisodeIfNeeded: failed to load persisted episode \(currentEpisodeID)",
        error
      )
    }
  }

  private func restorePendingPlaybackRequestIfNeeded() async {
    guard case .play(let episodeID) = pendingPlaybackRequest else { return }
    guard sharedState.onDeck?.id != episodeID else { return }

    Self.log.info("Loading episode \(episodeID) for pending playback")
    do {
      let podcastEpisode = try await repo.podcastEpisode(episodeID)
      guard case .play(let pendingEpisodeID) = pendingPlaybackRequest,
        pendingEpisodeID == episodeID
      else { return }
      guard let podcastEpisode else {
        Self.log.warning("Pending episode \(episodeID) not found in database")
        pendingPlaybackRequest = .none
        if sharedState.onDeck == nil && sharedState.currentEpisodeID == episodeID {
          stateManager.clearOnDeck()
        }
        return
      }
      try await load(podcastEpisode)
    } catch {
      Self.log.caughtError(
        "restorePendingPlaybackRequestIfNeeded: failed to load episode \(episodeID)",
        error
      )
    }
  }

  func restorePersistedEpisodeForForeground() async {
    await restorePendingPlaybackRequestIfNeeded()
    if case .play(let episodeID) = pendingPlaybackRequest {
      guard sharedState.onDeck?.id == episodeID else {
        Self.log.info("Pending playback for episode \(episodeID) remains deferred")
        return
      }
      await fulfillPendingPlaybackRequest()
      return
    }

    await restorePersistedEpisodeIfNeeded()
    await fulfillPendingPlaybackRequest()
  }

  @discardableResult
  func load(_ podcastEpisode: PodcastEpisode) async throws -> Bool {
    let loadID = claimLoadTransition()

    let task = Task<Bool, any Error> { [weak self] in
      guard let self else { return false }
      do {
        let loaded = try await performLoad(podcastEpisode, loadID: loadID)
        let outcome: LoadTransitionOutcome = loaded ? .succeeded : .didNotLoad
        await finishLoadTransition(loadID, outcome: outcome)
        return loaded
      } catch {
        await Task { [weak self] in
          guard let self else { return }
          await finishLoadTransition(loadID, outcome: .failed(podcastEpisode.id))
        }
        .value
        throw error
      }
    }

    loadTask = task
    return try await task.value
  }

  private func claimLoadTransition() -> UUID {
    let loadID = UUID()
    loadTransition = loadTransition ?? .init(id: loadID)
    loadTransition?.id = loadID
    loadTask?.cancel()
    return loadID
  }

  private func claimFinalization(
    of episodeID: Episode.ID,
    onDeckID: Episode.ID?
  ) -> UUID? {
    guard episodeID == onDeckID else { return nil }
    guard let transition = loadTransition else { return claimLoadTransition() }
    guard let establishedPlayback = transition.establishedPlayback,
      establishedPlayback.episodeID == episodeID,
      establishedPlayback.ownerID == transition.id
    else { return nil }
    return claimLoadTransition()
  }

  private func performLoad(_ incoming: PodcastEpisode, loadID: UUID) async throws -> Bool {
    let transition = loadTransition
    let outgoing = sharedState.onDeck

    if let outgoing, outgoing.id == incoming.id {
      try requireLoadTransitionOwnership(loadID)
      Self.log.debug("performLoad: ignoring \(incoming.toString), already loaded")
      return false
    }

    let outgoingEpisodeID: Episode.ID? =
      if let outgoing {
        outgoing.id
      } else if let currentEpisodeID = sharedState.currentEpisodeID,
        currentEpisodeID != incoming.id
      {
        currentEpisodeID
      } else {
        nil
      }

    let loadStart = Date()
    let outgoingDescription =
      if let outgoing {
        outgoing.toString
      } else if let outgoingEpisodeID {
        "persisted episode \(outgoingEpisodeID)"
      } else {
        "nil"
      }
    Self.log.info(
      """
      performLoad: starting
        incoming: \(incoming.toString)
        outgoing: \(outgoingDescription)
      """
    )

    var phaseStart = Date()
    Self.log.debug("performLoad: configuring audio session")
    let audioSessionConfigured = await Container.shared.configureAudioSession()()
    Self.log.debug(
      """
      performLoad: configured audio session result=\(audioSessionConfigured) \
      in \(Date().timeIntervalSince(phaseStart)) seconds
      """
    )
    guard audioSessionConfigured else { return false }
    try requireLoadTransitionOwnership(loadID)

    phaseStart = Date()
    Self.log.debug("performLoad: activating audio session")
    guard try activateAudioSessionForLoad() else { return false }
    try markAudioSessionOwned(by: loadID)
    Self.log.debug(
      "performLoad: activated audio session in \(Date().timeIntervalSince(phaseStart)) seconds"
    )

    try requireLoadTransitionOwnership(loadID)
    loadTransition?.state = .ownsPlaybackState
    do {
      // Do not mutate playback state until the audio session is ready. A
      // background activation can be rejected while another app is playing.
      phaseStart = Date()
      Self.log.debug("performLoad: removing player observers")
      await podAVPlayer.removeObservers()
      try requireLoadTransitionOwnership(loadID)
      Self.log.debug(
        "performLoad: removed player observers in \(Date().timeIntervalSince(phaseStart)) seconds"
      )

      if sharedState.stopAfterCurrentEpisode {
        Self.log.debug("performLoad: new episode starting, clearing stopAfterCurrentEpisode")
        sharedState.setStopAfterCurrentEpisode(false)
      }

      setStatus(.loading(incoming.episode.title))

      phaseStart = Date()
      Self.log.debug("performLoad: clearing onDeck")
      try await clearOnDeck(ownedBy: loadID)
      Self.log.debug(
        "performLoad: cleared onDeck in \(Date().timeIntervalSince(phaseStart)) seconds"
      )

      if let outgoingEpisodeID, transition?.finishedIDs.contains(outgoingEpisodeID) != true {
        let restoreStart = Date()
        Self.log.debug("performLoad: restoring outgoing episode to queue: \(outgoingDescription)")
        await Task { [weak self, transition] in
          guard let self else { return }
          do {
            try await self.queue.unshift(outgoingEpisodeID)
            if transition?.finishedIDs.contains(outgoingEpisodeID) == true {
              await self.cleanUpAfterLoadSuccess(outgoingEpisodeID)
              return
            }
            Self.log.debug(
              "performLoad: restored outgoing episode in \(Date().timeIntervalSince(restoreStart)) seconds: \(outgoingDescription)"
            )
          } catch {
            Self.log.caughtError(
              "performLoad: failed to unshift outgoing episode \(outgoingDescription)",
              error
            )
          }
        }
        .value
      } else {
        Self.log.debug("performLoad: no unfinished outgoing episode to restore")
      }

      try requireLoadTransitionOwnership(loadID)

      phaseStart = Date()
      Self.log.debug("performLoad: setting playback rate")
      await podAVPlayer.setRate(
        Float(incoming.podcast.defaultPlaybackRate ?? userSettings.defaultPlaybackRate)
      )
      try requireLoadTransitionOwnership(loadID)
      Self.log.debug(
        "performLoad: set playback rate in \(Date().timeIntervalSince(phaseStart)) seconds"
      )

      phaseStart = Date()
      Self.log.debug("performLoad: loading player item")
      let loaded = try await podAVPlayer.load(incoming)
      try requireLoadTransitionOwnership(loadID)
      Self.log.debug(
        """
        performLoad: loaded player item in \(Date().timeIntervalSince(phaseStart)) seconds
          loaded: \(loaded.toString)
        """
      )

      phaseStart = Date()
      Self.log.debug("performLoad: setting onDeck")
      try await setOnDeck(loaded, loadID: loadID)
      guard try shouldFinishEstablishedLoad(loadID) else { return true }
      Self.log.debug("performLoad: set onDeck in \(Date().timeIntervalSince(phaseStart)) seconds")

      phaseStart = Date()
      Self.log.debug("performLoad: cleaning up after load success")
      await cleanUpAfterLoadSuccess(incoming.id)
      guard try shouldFinishEstablishedLoad(loadID) else { return true }
      Self.log.debug(
        """
        performLoad: cleaned up after load success in \
        \(Date().timeIntervalSince(phaseStart)) seconds
        """
      )

      phaseStart = Date()
      Self.log.debug("performLoad: adding player observers")
      await podAVPlayer.addObservers()
      guard try shouldFinishEstablishedLoad(loadID) else { return true }
      let playbackStatus = await podAVPlayer.playbackStatus()
      guard try shouldFinishEstablishedLoad(loadID) else { return true }
      setStatus(playbackStatus)
      loadTransition?.state = .preservingPlayback
      Self.log.debug(
        """
        performLoad: completed in \(Date().timeIntervalSince(loadStart)) seconds
          addObservers: \(Date().timeIntervalSince(phaseStart)) seconds
        """
      )
      return true
    } catch {
      await Task { [weak self, outgoing, incoming] in
        guard let self else { return }

        await cleanUpAfterLoadFailure(outgoing, incoming)
      }
      .value

      throw error
    }
  }

  private func cleanUpAfterLoadSuccess(_ episodeID: Episode.ID) async {
    Self.log.debug("cleanUpAfterLoadSuccess: dequeueing episode \(episodeID)")
    do {
      try await queue.dequeue(episodeID)
    } catch {
      Self.log.caughtError(
        "cleanUpAfterLoadSuccess: failed to dequeue episode \(episodeID)",
        error
      )
    }
  }

  private func cleanUpAfterLoadFailure(
    _ outgoing: OnDeck?,
    _ incoming: PodcastEpisode
  ) async {
    let nowOnDeck = sharedState.onDeck

    Self.log.debug(
      """
      cleanUpAfterLoadFailure
        outgoing: \(String(describing: outgoing?.toString))
        incoming: \(incoming.toString)
        nowOnDeck: \(String(describing: nowOnDeck?.toString))
      """
    )

    if incoming.id != nowOnDeck?.id {
      Self.log.debug(
        """
        cleanUpAfterLoadFailure: unshifting incoming episode post failure: \
        \(incoming.toString)
        """
      )
      do {
        try await queue.unshift(incoming.id)
      } catch {
        Self.log.caughtError(
          "cleanUpAfterLoadFailure: failed to unshift incoming episode \(incoming.toString)",
          error
        )
      }
    }
  }

  private func requireLoadTransitionOwnership(_ loadID: UUID) throws {
    try Task.checkCancellation()
    guard loadTransition?.id == loadID else { throw CancellationError() }
  }

  private func shouldFinishEstablishedLoad(_ loadID: UUID) throws -> Bool {
    guard loadTransition?.id == loadID else { return false }
    try Task.checkCancellation()
    return true
  }

  private func markAudioSessionOwned(by loadID: UUID) throws {
    try requireLoadTransitionOwnership(loadID)
    guard loadTransition?.state == .preservingPlayback else { return }
    loadTransition?.state = .ownsAudioSession
  }

  private func finishLoadTransition(
    _ loadID: UUID,
    outcome: LoadTransitionOutcome
  ) async {
    guard let transition = loadTransition, transition.id == loadID else { return }

    if case .failed(let episodeID) = outcome,
      case .play(let pendingEpisodeID) = pendingPlaybackRequest,
      pendingEpisodeID == episodeID
    {
      pendingPlaybackRequest = .none
    }

    switch outcome {
    case .succeeded:
      loadTransition = nil
    case .didNotLoad, .failed:
      switch transition.state {
      case .preservingPlayback:
        loadTransition = nil
      case .ownsAudioSession:
        if sharedState.onDeck == nil {
          setStatus(.stopped)
        }
        loadTransition = nil
      case .ownsPlaybackState:
        do {
          try await clearOnDeck(ownedBy: loadID)
          try requireLoadTransitionOwnership(loadID)
        } catch is CancellationError {
          return
        } catch {
          Self.log.caughtError("finishLoadTransition: failed to clear playback state", error)
          return
        }
        setStatus(.stopped)
        loadTransition = nil
      case .establishedPlayback(let episodeID):
        await cleanUpAfterLoadSuccess(episodeID)
        guard loadTransition?.id == loadID else { return }
        await podAVPlayer.addObservers()
        guard loadTransition?.id == loadID else { return }
        loadTransition = nil
      }
    }
  }

  private func clearOnDeck(ownedBy loadID: UUID) async throws {
    try requireLoadTransitionOwnership(loadID)
    Self.log.debug("clearOnDeck: executing for owned load transition")
    imageFetchTask?.cancel()
    await podAVPlayer.clear()
    try requireLoadTransitionOwnership(loadID)
    NowPlayingInfo.clear()
    stateManager.clearOnDeck()
    onDeckBecameCurrentAt = nil
    CommandCenter.updateNextTrack()
  }

  func play(_ podcastEpisode: PodcastEpisode) async throws {
    pendingPlaybackRequest = .play(podcastEpisode.id)
    try await load(podcastEpisode)

    guard case .play(let pendingEpisodeID) = pendingPlaybackRequest,
      pendingEpisodeID == podcastEpisode.id,
      sharedState.onDeck?.id == podcastEpisode.id
    else { return }
    await fulfillPendingPlaybackRequest()
  }

  func play() async {
    guard let episodeID = sharedState.onDeck?.id ?? sharedState.currentEpisodeID else {
      pendingPlaybackRequest = .none
      Self.log.warning("play: nothing to play")
      return
    }
    pendingPlaybackRequest = .play(episodeID)

    await restorePersistedEpisodeIfNeeded()
    await fulfillPendingPlaybackRequest()
  }

  private func fulfillPendingPlaybackRequest() async {
    guard case .play(let episodeID) = pendingPlaybackRequest else { return }
    guard let onDeck = sharedState.onDeck else {
      if sharedState.currentEpisodeID == episodeID {
        Self.log.info("play: deferring episode \(episodeID) until persisted playback is restored")
      } else {
        pendingPlaybackRequest = .none
        Self.log.warning("play: nothing to play")
      }
      return
    }
    guard onDeck.id == episodeID else {
      pendingPlaybackRequest = .none
      Self.log.warning(
        "play: dropping stale request for episode \(episodeID); on-deck episode is \(onDeck.id)"
      )
      return
    }

    pendingPlaybackRequest = .none
    await podAVPlayer.play()
  }

  func pause() async {
    pendingPlaybackRequest = .none
    await podAVPlayer.pause()
  }

  func stop() async {
    pendingPlaybackRequest = .none
    await clearOnDeck()
    setStatus(.stopped)
  }

  func stop(ifCurrentEpisodeIDIs episodeID: Episode.ID) async -> Bool {
    guard sharedState.currentEpisodeID == episodeID else { return false }
    await stop()
    return true
  }

  func toggle() async {
    await podAVPlayer.toggle()
  }

  func finishEpisode(_ episodeID: Episode.ID? = nil) async {
    let onDeckID = sharedState.onDeck?.id
    let episodeID = episodeID ?? onDeckID
    guard let episodeID else { return }
    Self.log.debug("finishEpisode: \(episodeID) (onDeckID: \(String(describing: onDeckID)))")
    let finalizationID = claimFinalization(of: episodeID, onDeckID: onDeckID)
    if finalizationID != nil,
      case .play(let pendingEpisodeID) = pendingPlaybackRequest,
      pendingEpisodeID == episodeID
    {
      pendingPlaybackRequest = .none
    }
    loadTransition?.finishedIDs.insert(episodeID)
    if episodeID == onDeckID { loadTransition?.state = .ownsPlaybackState }
    do {
      try await repo.markFinished(episodeID)
    } catch {
      Self.log.caughtError("finishEpisode: failed to mark episode \(episodeID) finished", error)
    }

    guard let finalizationID else {
      await cleanUpAfterLoadSuccess(episodeID)
      return
    }
    do {
      try requireLoadTransitionOwnership(finalizationID)
      suppressRemoteScrubCommands()
      try await clearOnDeck(ownedBy: finalizationID)
      if sharedState.stopAfterCurrentEpisode {
        Self.log.debug("finishEpisode: stopAfterCurrentEpisode set, stopping instead of advancing")
        sharedState.setStopAfterCurrentEpisode(false)
        setStatus(.stopped)
        loadTransition = nil
        return
      }

      let nextEpisode = try await queue.nextEpisode
      try requireLoadTransitionOwnership(finalizationID)
      if let nextEpisode {
        Self.log.debug("next episode exists to automatically load: \(nextEpisode.toString)")
        guard try await load(nextEpisode), settledOnDeckID == nextEpisode.id else { return }
        await play()
        return
      }

      let recommended = try await nextAutoplayRecommendation()
      try requireLoadTransitionOwnership(finalizationID)
      if let recommended {
        Self.log.debug("autoloading queue-empty recommendation: \(recommended.toString)")
        guard try await load(recommended), settledOnDeckID == recommended.id else { return }
        await play()
        return
      }
      Self.log.debug("no automatic replacement episode, stopping")
      setStatus(.stopped)
      loadTransition = nil
    } catch is CancellationError {
      if loadTransition?.id == finalizationID {
        if sharedState.onDeck == nil { setStatus(.stopped) }
        loadTransition = nil
      }
      return
    } catch {
      Self.log.caughtError("finishEpisode: failed to load next episode after \(episodeID)", error)
      if loadTransition?.id == finalizationID {
        setStatus(.stopped)
        loadTransition = nil
      } else if sharedState.onDeck == nil, loadTransition == nil {
        setStatus(.stopped)
      }
      await alert(ErrorKit.message(for: error))
    }
  }

  // Filters published IDs by current state; `finishDate` excludes the finished episode.
  private func nextAutoplayRecommendation() async throws -> PodcastEpisode? {
    guard userSettings.autoPlayTopRecommendationWhenQueueEmpty else { return nil }
    for episodeID in sharedState.recommendedEpisodePool {
      guard let podcastEpisode = try await repo.podcastEpisode(episodeID) else {
        Self.log.warning(
          "nextAutoplayRecommendation: ranked episode \(episodeID) not found in database, skipping"
        )
        continue
      }
      guard podcastEpisode.isCandidate else { continue }
      return podcastEpisode
    }
    return nil
  }

  // MARK: - Cache

  func toggleSaveInCache(_ episodeID: Episode.ID) async {
    let alreadySaved: Bool
    do {
      guard let episode = try await repo.episode(episodeID) else {
        Self.log.warning("toggleSaveInCache: episode \(episodeID) not found")
        return
      }
      alreadySaved = episode.saveInCache
    } catch {
      Self.log.caughtError("toggleSaveInCache: failed to load episode \(episodeID)", error)
      return
    }
    Self.log.debug("toggleSaveInCache: \(episodeID) alreadySaved: \(alreadySaved)")

    if alreadySaved {
      await unsaveInCache(episodeID)
    } else {
      await saveInCache(episodeID)
    }
  }

  private func saveInCache(_ episodeID: Episode.ID) async {
    Self.log.debug("saveInCache: \(episodeID)")
    do {
      try await repo.updateSaveInCache(episodeID, saveInCache: true)
    } catch {
      Self.log.caughtError("saveInCache: failed to set saveInCache for episode \(episodeID)", error)
      return
    }
    do {
      try await cacheManager.downloadToCache(for: episodeID)
    } catch {
      Self.log.caughtError("saveInCache: failed to cache episode \(episodeID)", error)
    }
  }

  private func unsaveInCache(_ episodeID: Episode.ID) async {
    Self.log.debug("unsaveInCache: \(episodeID)")
    do {
      try await repo.updateSaveInCache(episodeID, saveInCache: false)
    } catch {
      Self.log.caughtError(
        "unsaveInCache: failed to unset saveInCache for episode \(episodeID)",
        error
      )
    }
  }

  // MARK: - Remote Scrub Suppression

  // Snapshot Now Playing state after a pause to diagnose delayed system scrub commands.
  func startPostPauseObservation() {
    postPauseObservationTask?.cancel()
    postPauseObservationTask = Task { [weak self] in
      guard let self else { return }
      let pauseAt = Date()
      for _ in 0..<9 {
        do {
          try await sleeper.sleep(for: .seconds(5))
        } catch {
          return
        }
        if Task.isCancelled { return }
        let offset = Int(Date().timeIntervalSince(pauseAt).rounded())
        await logBackgroundPlaybackSnapshot(
          label: "post-pause +\(offset)s",
          currentTime: podAVPlayer.currentTime()
        )
      }
      // Clear only on graceful completion. The cancel path returns early so a
      // replacement task assigned to this property isn't wiped out.
      postPauseObservationTask = nil
    }
  }

  // Temporarily suppress remote scrub commands after episode transitions.
  // iOS may deliver stale scrub events from the finished episode's gesture
  // with the NEW episode's ID (captured at delivery time, not gesture time),
  // bypassing the episodeID guard.
  private func suppressRemoteScrubCommands() {
    restartScrubCommandsTask?.cancel()
    ignoreRemoteScrubCommands = true
    Self.log.debug("suppressing remote scrubs for \(remoteScrubSuppressionDuration)")
    restartScrubCommandsTask = Task { [weak self] in
      guard let self else { return }
      try await sleeper.sleep(for: remoteScrubSuppressionDuration)
      try Task.checkCancellation()
      ignoreRemoteScrubCommands = false
      Self.log.debug("re-enabling remote scrubs after suppression window")
    }
  }

  // MARK: - Seeking

  func seekForward(_ interval: TimeInterval? = nil) async {
    let duration = interval ?? userSettings.skipForwardInterval
    let currentTime = await podAVPlayer.currentTime()
    await seek(to: currentTime + CMTime.seconds(duration))
  }

  func seekBackward(_ interval: TimeInterval? = nil) async {
    let duration = interval ?? userSettings.skipBackwardInterval
    let currentTime = await podAVPlayer.currentTime()
    await seek(to: currentTime - CMTime.seconds(duration))
  }

  func seek(to time: CMTime) async {
    NowPlayingInfo.setCurrentTime(time)
    await podAVPlayer.seek(to: time)
  }

  // MARK: - Chapter Navigation

  func seekToNextChapter() async {
    guard let chapters = sharedState.onDeck?.chapters, !chapters.isEmpty else {
      await seekForward()
      return
    }

    let currentSeconds = (sharedState.onDeck?.currentTime ?? .zero).seconds
    if let nextChapter = chapters.first(where: { $0.seconds > currentSeconds }) {
      await seek(to: nextChapter)
    } else {
      await finishEpisode()
    }
  }

  func seekToPreviousChapter() async {
    guard let chapters = sharedState.onDeck?.chapters, !chapters.isEmpty else {
      await seekBackward()
      return
    }

    let currentSeconds = (sharedState.onDeck?.currentTime ?? .zero).seconds
    let previousChapters = chapters.filter { $0.seconds < currentSeconds }

    let targetTime: CMTime
    if let nearestPrevious = previousChapters.last {
      if currentSeconds - nearestPrevious.seconds < 2 {
        targetTime =
          previousChapters.count > 1 ? previousChapters[previousChapters.count - 2] : .zero
      } else {
        targetTime = nearestPrevious
      }
    } else {
      targetTime = .zero
    }

    await seek(to: targetTime)
  }

  // Incoming command from user input (in contrast to setPlaybackRate(_))
  func setRate(_ rate: Float) async {
    Assert.precondition(rate > 0, "Setting playback rate to 0?")

    sharedState.setPlayRate(rate)
    await podAVPlayer.setRate(rate)
  }

  // MARK: - State Management

  private func setOnDeck(_ podcastEpisode: PodcastEpisode, loadID: UUID) async throws {
    try requireLoadTransitionOwnership(loadID)
    Self.log.debug("setOnDeck: \(podcastEpisode.toString)")

    NowPlayingInfo.setOnDeck(podcastEpisode)
    stateManager.setOnDeck(podcastEpisode)
    loadTransition?.state = .establishedPlayback(podcastEpisode.id)
    loadTransition?.establishedPlayback = (podcastEpisode.id, loadID)
    onDeckBecameCurrentAt = Date()
    CommandCenter.updateNextTrack()
    fetchImage(for: podcastEpisode)

    if podcastEpisode.episode.currentTime != CMTime.zero {
      Self.log.debug(
        """
        setOnDeck: Seeking \(podcastEpisode.toString), to \
        currentTime: \(podcastEpisode.episode.currentTime)
        """
      )
      await seek(to: podcastEpisode.episode.currentTime)
    } else {
      setCurrentTime(.zero)
    }
  }

  private func fetchImage(for podcastEpisode: PodcastEpisode) {
    let imageURL =
      userSettings.alwaysShowPodcastImageForOnDeck
      ? podcastEpisode.podcastImage : podcastEpisode.image
    fetchImage(episodeID: podcastEpisode.id, imageURL: imageURL)
  }

  private func fetchImage(episodeID: Episode.ID, imageURL: URL) {
    imageFetchTask?.cancel()

    imageFetchTask = Task { [weak self, episodeID, imageURL] in
      guard let self else { return }
      do {
        let image = try await imagePipeline.image(for: imageURL)
        guard !Task.isCancelled else { return }

        stateManager.setArtwork(image, for: episodeID)
        NowPlayingInfo.setImage(image)
      } catch {
        Self.log.caughtError(
          "fetchImage: failed to load image \(imageURL) for episode \(episodeID)",
          error
        )
      }
    }
  }

  func refetchOnDeckImage() {
    guard let onDeck = sharedState.onDeck else { return }
    let imageURL =
      userSettings.alwaysShowPodcastImageForOnDeck ? onDeck.podcastImage : onDeck.image
    fetchImage(episodeID: onDeck.id, imageURL: imageURL)
  }

  func clearOnDeck() async {
    Self.log.debug("clearOnDeck: executing")
    imageFetchTask?.cancel()
    await podAVPlayer.clear()
    NowPlayingInfo.clear()
    stateManager.clearOnDeck()
    onDeckBecameCurrentAt = nil
    CommandCenter.updateNextTrack()
  }

  func setCurrentTime(_ currentTime: CMTime) {
    let now = Date()
    if now.timeIntervalSince(lastLoggedTime) >= 10 {
      lastLoggedTime = now
      Self.log.debug("setCurrentTime: \(currentTime)")
    }
    stateManager.setCurrentTime(currentTime)

    // Periodically anchor lock-screen elapsed time because system extrapolation can drift.
    if abs(currentTime.seconds - (lastNowPlayingElapsedWrite ?? .zero).seconds) >= 3.0 {
      lastNowPlayingElapsedWrite = currentTime
      NowPlayingInfo.setCurrentTime(currentTime)
    }

    // Snapshot player and lock-screen state periodically for background diagnostics.
    if let last = lastBackgroundSnapshot {
      let snapshotDelta = now.timeIntervalSince(last)
      if snapshotDelta >= 30 {
        lastBackgroundSnapshot = now
        Task { [weak self, currentTime, snapshotDelta] in
          guard let self else { return }
          let offset = Int(snapshotDelta.rounded())
          await logBackgroundPlaybackSnapshot(
            label: "periodic +\(offset)s",
            currentTime: currentTime
          )
        }
      }
    } else {
      lastBackgroundSnapshot = now
    }
  }

  func setStatus(_ status: PlaybackStatus) {
    Self.log.debug("setStatus: \(status)")
    sharedState.setPlaybackStatus(status)

    if status == .stopped {
      do {
        try Container.shared.setAudioSessionActive()(false)
      } catch {
        Self.log.caughtError(
          "setStatus: failed to deactivate audio session",
          error,
          level: .notice
        )
      }
    }
  }

  // Incoming state update from the AVPlayer (in contrast to setRate(_))
  func setPlaybackRate(_ rate: Float) {
    Self.log.debug("setPlaybackRate: \(rate)")
    NowPlayingInfo.setPlaybackRate(rate)
    sharedState.setPlayRate(rate)
  }
}
