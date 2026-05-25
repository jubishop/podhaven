// Copyright Justin Bishop, 2025

import AVFoundation
import Combine
import FactoryKit
import Foundation
import GRDB
import Logging
import Nuke
import SwiftUI
import Tagged

extension Container {
  // Retries because mediaservicesd is sometimes dead at launch (e.g., right
  // after a TestFlight install/update) and typically respawns within seconds.
  var configureAudioSession: Factory<@Sendable () async -> Bool> {
    Factory(self) {
      {
        PlayManager.log.info("configureAudioSession: executing")

        let maxAttempts = 5
        let maxDelay: Duration = .seconds(2)
        var retryDelay: Duration = .milliseconds(250)

        for attempt in 1...maxAttempts {
          do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .spokenAudio, policy: .longFormAudio)
            try session.setMode(.spokenAudio)
            PlayManager.log.info(
              """
              configureAudioSession: configured (attempt \(attempt)/\(maxAttempts))
                category: \(session.category.rawValue)
                mode: \(session.mode.rawValue)
                routeSharingPolicy: \(session.routeSharingPolicy.rawValue)
              """
            )
            return true
          } catch {
            if attempt == maxAttempts {
              PlayManager.log.caughtError(
                "configureAudioSession: failed after \(maxAttempts) attempts",
                error
              )
              await Container.shared.alert()(
                title: "Couldn't start audio playback",
                ErrorKit.message(for: error)
              )
              return false
            }
            PlayManager.log.debug(
              """
              configureAudioSession: attempt \(attempt)/\(maxAttempts) failed, \
              retrying in \(retryDelay)
                error: \(ErrorKit.message(for: error))
              """
            )
            do {
              try await Container.shared.sleeper().sleep(for: retryDelay)
            } catch {
              PlayManager.log.caughtError(
                """
                configureAudioSession: cancelled during retry backoff \
                (attempt \(attempt)/\(maxAttempts))
                """,
                error
              )
              return false
            }
            retryDelay = min(retryDelay * 2, maxDelay)
          }
        }
        return false
      }
    }
    .scope(.cached)
  }

  var setAudioSessionActive: Factory<(Bool) throws -> Void> {
    Factory(self) {
      { active in
        let audioSession = AVAudioSession.sharedInstance()
        try audioSession.setActive(active)
      }
    }
  }

  var playManager: Factory<PlayManager> {
    Factory(self) { PlayManager() }.scope(.cached)
  }
}

@globalActor
actor PlayActor {
  static let shared = PlayActor()
}

@PlayActor
final class PlayManager {
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

  nonisolated static let log = Log.as(LogSubsystem.Play.manager)

  // MARK: - Configurable Constants

  let recoveryDebounceInterval: TimeInterval = 5
  private let remoteScrubSuppressionDuration: Duration = .milliseconds(500)

  // MARK: - State Management

  var lastRecoveryAttempt: (episodeID: Episode.ID, time: Date)?
  private var imageFetchTask: Task<Void, Never>?
  private var loadTask: Task<Bool, any Error>?
  private let startOnce = AsyncOnce()
  private let startStreamConsumersOnce = Once()
  private(set) var ignoreRemoteScrubCommands = false
  private var restartScrubCommandsTask: Task<Void, any Error>?
  private var lastLoggedTime = Date.distantPast
  private var lastNowPlayingElapsedWrite: CMTime?
  private var lastBackgroundSnapshot: Date?
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
      await self.loadPersistedEpisodeIfNeeded()
    }
  }

  private func loadPersistedEpisodeIfNeeded() async {
    guard sharedState.onDeck == nil else { return }
    guard let currentEpisodeID = sharedState.currentEpisodeID else { return }

    Self.log.info("Loading persisted episode \(currentEpisodeID)")
    do {
      guard let podcastEpisode = try await repo.podcastEpisode(currentEpisodeID) else {
        Self.log.warning("Persisted episode \(currentEpisodeID) not found in database")
        return
      }
      try await load(podcastEpisode)
    } catch {
      Self.log.caughtError(
        "loadPersistedEpisodeIfNeeded: failed to load persisted episode \(currentEpisodeID)",
        error
      )
    }
  }

  // MARK: - Loading

  @discardableResult
  func load(_ podcastEpisode: PodcastEpisode) async throws -> Bool {
    loadTask?.cancel()
    return try await performLoad(podcastEpisode)
  }

  private func performLoad(_ incoming: PodcastEpisode) async throws -> Bool {
    let outgoing = sharedState.onDeck

    if let outgoing, outgoing.id == incoming.id {
      Self.log.debug("performLoad: ignoring \(incoming.toString), already loaded")
      return false
    }

    let task = Task<Bool, any Error> { [weak self] in
      guard let self else { return false }
      Self.log.info("performLoad: \(incoming.toString)")

      await podAVPlayer.removeObservers()
      setStatus(.loading(incoming.episode.title))
      await clearOnDeck()

      // Restore the outgoing episode to the top of the queue immediately so
      // it stays visible for the entire load attempt. Without this, a long
      // network load (or a timeout, ~12s in the field) leaves the
      // previously-OnDeck episode in limbo — neither OnDeck nor in the
      // queue — until cleanUpAfterLoad{Success,Failure} runs at the end.
      if let outgoing {
        do {
          try await queue.unshift(outgoing.id)
        } catch {
          Self.log.caughtError(
            "performLoad: failed to unshift outgoing episode \(outgoing.toString)",
            error
          )
        }
      }

      guard await Container.shared.configureAudioSession()() else {
        await cleanUpAfterLoadFailure(outgoing, incoming)
        return false
      }

      do {
        try Container.shared.setAudioSessionActive()(true)
        Self.log.debug("performLoad: audio session activated")
        await podAVPlayer.setRate(
          Float(incoming.podcast.defaultPlaybackRate ?? userSettings.defaultPlaybackRate)
        )
        let loaded = try await podAVPlayer.load(incoming)
        try await setOnDeck(loaded)
      } catch {
        await Task { [weak self, outgoing, incoming] in  // Task to execute even inside cancellation
          guard let self else { return }

          await cleanUpAfterLoadFailure(outgoing, incoming)
        }
        .value

        throw error
      }

      await cleanUpAfterLoadSuccess(outgoing, incoming)
      await podAVPlayer.addObservers()
      return true
    }

    loadTask = task
    return try await task.value
  }

  private func cleanUpAfterLoadSuccess(_ outgoing: OnDeck?, _ incoming: PodcastEpisode) async {
    Self.log.debug(
      """
      cleanUpAfterLoadSuccess
        outgoing: \(String(describing: outgoing?.toString))
        incoming: \(incoming.toString)
      """
    )

    Self.log.debug("cleanUpAfterLoadSuccess: dequeueing incoming episode: \(incoming.toString)")
    do {
      try await queue.dequeue(incoming.id)
    } catch {
      Self.log.caughtError(
        "cleanUpAfterLoadSuccess: failed to dequeue incoming episode \(incoming.toString)",
        error
      )
    }
  }

  private func cleanUpAfterLoadFailure(_ outgoing: OnDeck?, _ incoming: PodcastEpisode) async {
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

    if let nowOnDeck {
      Self.log.debug(
        """
        cleanUpAfterLoadFailure: no stopping after load failure because new podcast seems \
        to have loaded
          Failed to load: \(String(describing: incoming.toString)) \
          Loaded instead: \(nowOnDeck.toString)
        """
      )
    } else {
      await stop()
    }
  }

  // MARK: - Playback Controls

  func play() async {
    await loadPersistedEpisodeIfNeeded()

    guard sharedState.onDeck != nil else {
      Self.log.warning("play: nothing to play")
      return
    }

    await podAVPlayer.play()
  }

  func pause() async {
    await podAVPlayer.pause()
  }

  func stop() async {
    await clearOnDeck()
    setStatus(.stopped)
  }

  func toggle() async {
    await podAVPlayer.toggle()
  }

  func finishEpisode(_ episodeID: Episode.ID? = nil) async {
    let onDeckID = sharedState.onDeck?.id
    let episodeID = episodeID ?? onDeckID
    guard let episodeID else { return }
    Self.log.debug("finishEpisode: \(episodeID) (onDeckID: \(String(describing: onDeckID)))")

    do {
      try await repo.markFinished(episodeID)
    } catch {
      Self.log.caughtError("finishEpisode: failed to mark episode \(episodeID) finished", error)
    }

    guard episodeID == onDeckID
    else { return }

    suppressRemoteScrubCommands()

    await clearOnDeck()

    do {
      if let nextEpisode = try await queue.nextEpisode {
        Self.log.debug("next episode exists to automatically load: \(nextEpisode.toString)")

        try await load(nextEpisode)
        await play()
      } else if let recommended = try await nextAutoplayRecommendation() {
        Self.log.debug(
          """
          queue empty, autoloading top recommendation: \(recommended.toString) \
          (autoPlayTopRecommendationWhenQueueEmpty enabled)
          """
        )

        try await load(recommended)
        await play()
      } else {
        Self.log.debug(
          """
          no next episode, stopping \
          (autoPlayTopRecommendationWhenQueueEmpty: \
          \(userSettings.autoPlayTopRecommendationWhenQueueEmpty), \
          recommendedPoolCount: \(sharedState.recommendedEpisodePool.count))
          """
        )
        setStatus(.stopped)
      }
    } catch {
      Self.log.caughtError("finishEpisode: failed to load next episode after \(episodeID)", error)
      await alert(ErrorKit.message(for: error))
    }
  }

  // Returns the first pool entry that's still candidate-eligible. The pool
  // is published as IDs only, so anything that's been queued / rated /
  // finished / started since the last engine rebuild has to be filtered out
  // here. OnDeck is excluded too — autoplay must pick the *next* episode.
  private func nextAutoplayRecommendation() async throws -> PodcastEpisode? {
    guard userSettings.autoPlayTopRecommendationWhenQueueEmpty else { return nil }
    let onDeckID = sharedState.onDeck?.id
    for episodeID in sharedState.recommendedEpisodePool where episodeID != onDeckID {
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

  // MARK: - Remote Scrub Suppression

  // After an AirPods-triggered pause, fire snapshots every 5s for 45s so the
  // dict state across the ~30s window before iOS's system-generated stale
  // scrub is captured. If any snapshot shows ElapsedPlaybackTime drifting
  // from what the pause handler wrote, iOS is rewriting the dict during that
  // window. If the dict stays put but the scrub still arrives with a
  // different value, iOS is sourcing the position from somewhere else
  // entirely (mediaserverd theory). See memory/project_nowplaying_desync_bug.md.
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
    restartScrubCommandsTask = Task { [weak self] in
      guard let self else { return }
      try await sleeper.sleep(for: remoteScrubSuppressionDuration)
      try Task.checkCancellation()
      ignoreRemoteScrubCommands = false
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

  private func setOnDeck(_ podcastEpisode: PodcastEpisode) async throws {
    Self.log.debug("setOnDeck: \(podcastEpisode.toString)")

    NowPlayingInfo.setOnDeck(podcastEpisode)
    stateManager.setOnDeck(podcastEpisode)
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
    CommandCenter.updateNextTrack()
  }

  func setCurrentTime(_ currentTime: CMTime) {
    let now = Date()
    if now.timeIntervalSince(lastLoggedTime) >= 10 {
      lastLoggedTime = now
      Self.log.debug("setCurrentTime: \(currentTime)")
    }
    stateManager.setCurrentTime(currentTime)

    // Periodically anchor iOS's lock-screen extrapolation. Apple's docs say
    // explicit periodic updates are unnecessary, but incidents 1–5 in
    // memory/project_nowplaying_desync_bug.md show iOS's extrapolation drifts
    // backward during long background sessions. Writing every 3 seconds of
    // playback-time delta caps worst-case dict staleness at ~3s. Event-driven
    // writes (seek, play/pause, rate change) also flow through
    // `NowPlayingInfo.setCurrentTime` directly and are unaffected by this gate.
    if abs(currentTime.seconds - (lastNowPlayingElapsedWrite ?? .zero).seconds) >= 3.0 {
      lastNowPlayingElapsedWrite = currentTime
      NowPlayingInfo.setCurrentTime(currentTime)
    }

    // Every 30s wall-clock, snapshot both our AVPlayer view and iOS's dict
    // view so the next stale-scrub incident has a trail of checkpoints
    // covering the whole session. Tight post-pause resolution comes from
    // `startPostPauseObservation` at 5s; during normal playback 30s keeps
    // the daily log budget around ~250KB so 24h of retention stays within
    // the 3MB log rotation. See memory/project_nowplaying_desync_bug.md.
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
        Self.log.caughtError("setStatus: failed to deactivate audio session", error)
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
