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
  var configureAudioSession: Factory<() throws -> Void> {
    Factory(self) {
      {
        let audioSession = AVAudioSession.sharedInstance()
        try audioSession.setCategory(.playback, mode: .spokenAudio, policy: .longFormAudio)
        try audioSession.setMode(.spokenAudio)
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
    Factory(self) { @PlayActor in PlayManager() }.scope(.cached)
  }
}

@globalActor
actor PlayActor {
  static let shared = PlayActor()
}

@PlayActor
final class PlayManager {
  @DynamicInjected(\.cacheManager) private var cacheManager
  @DynamicInjected(\.commandCenterStream) private var commandCenterStream
  @DynamicInjected(\.fileManager) private var fileManager
  @DynamicInjected(\.imagePipeline) private var imagePipeline
  @DynamicInjected(\.notifications) private var notifications
  @DynamicInjected(\.observatory) private var observatory
  @DynamicInjected(\.queue) private var queue
  @DynamicInjected(\.repo) private var repo
  @DynamicInjected(\.sharedState) private var sharedState
  @DynamicInjected(\.sleeper) private var sleeper
  @DynamicInjected(\.stateManager) private var stateManager
  @DynamicInjected(\.userSettings) private var userSettings

  private var alert: Alert { get async { await Container.shared.alert() } }
  private var podAVPlayer: PodAVPlayer { get async { await Container.shared.podAVPlayer() } }

  nonisolated private static let log = Log.as(LogSubsystem.Play.manager)

  // MARK: - Configurable Constants

  let seekIgnoreTime: Duration = .seconds(1)
  let recoveryDebounceInterval: TimeInterval = 5

  // MARK: - State Management

  private var lastRecoveryAttempt: (episodeID: Episode.ID, time: Date)?
  private var imageFetchTask: Task<Void, Never>?
  private var loadTask: Task<Bool, any Error>?
  private var restartSeekCommandsTask: Task<Void, any Error>?
  private var ignoreSeekCommands = false

  // MARK: - Initialization

  fileprivate init() {}

  // Starts the async stream consumers for command center and notifications.
  // Called from AppDelegate after audio session and command handlers are configured.
  nonisolated func startStreamConsumers() {
    guard Function.neverCalled() else { return }
    Self.log.debug("startStreamConsumers: executing")

    notificationTracking()
    asyncStreams()
  }

  // Full startup for foreground use (called when app becomes active).
  // Loads the current episode if one exists.
  // Note: Audio session and command handlers must already be configured.
  func start() async {
    guard Function.neverCalled() else { return }
    Self.log.debug("start: executing")

    startStreamConsumers()
    await loadPersistedEpisodeIfNeeded()
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

  @discardableResult
  func configureAudioSession() -> Bool {
    Self.log.info("configureAudioSession: executing")
    do {
      try Container.shared.configureAudioSession()()
      let session = AVAudioSession.sharedInstance()
      Self.log.info(
        """
        configureAudioSession: configured
          category: \(session.category.rawValue)
          mode: \(session.mode.rawValue)
          routeSharingPolicy: \(session.routeSharingPolicy.rawValue)
        """
      )
    } catch {
      Self.log.caughtError("configureAudioSession: failed to configure audio session", error)
      Task { @MainActor [weak self] in
        guard let self else { return }
        await alert("Couldn't get audio permissions") {
          Button("Send Report and Crash") {
            Assert.fatal("Failed to initialize the audio session")
          }
        }
      }
      return false
    }
    return true
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
      await setStatus(.loading(incoming.episode.title))
      await clearOnDeck()

      do {
        guard configureAudioSession() else { return false }
        try Container.shared.setAudioSessionActive()(true)
        Self.log.debug("performLoad: audio session activated")
        await podAVPlayer.setRate(
          Float(incoming.podcast.defaultPlaybackRate ?? userSettings.defaultPlaybackRate)
        )
        try await setOnDeck(try await podAVPlayer.load(incoming))
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

    // Dequeue since we successfully loaded the episode
    Self.log.debug("cleanUpAfterLoadSuccess: dequeueing incoming episode: \(incoming.toString)")
    do {
      try await queue.dequeue(incoming.id)
    } catch {
      Self.log.caughtError(
        "cleanUpAfterLoadSuccess: failed to dequeue incoming episode \(incoming.toString)",
        error
      )
    }

    // If there was an outgoing episode, put it back at the front of the queue
    if let outgoing {
      Self.log.debug("cleanUpAfterLoadSuccess: unshifting outgoing episode: \(outgoing.toString)")
      do {
        try await queue.unshift(outgoing.id)
      } catch {
        Self.log.caughtError(
          "cleanUpAfterLoadSuccess: failed to unshift outgoing episode \(outgoing.toString)",
          error
        )
      }
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

    // Put the outgoing episode back if we displaced it
    if let outgoing, outgoing.id != nowOnDeck?.id {
      Self.log.debug(
        """
        cleanUpAfterLoadFailure: unshifting outgoing episode post failure: \
        \(outgoing.toString)
        """
      )
      do {
        try await queue.unshift(outgoing.id)
      } catch {
        Self.log.caughtError(
          "cleanUpAfterLoadFailure: failed to unshift outgoing episode \(outgoing.toString)",
          error
        )
      }
    }

    // Put the incoming episode back at the front of the queue since it failed to load
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
    await setStatus(.stopped)
  }

  func toggle() async {
    await podAVPlayer.toggle()
  }

  func finishEpisode(_ episodeID: Episode.ID? = nil) async {
    Self.log.debug("finishEpisode: \(String(describing: episodeID))")

    let onDeckID = sharedState.onDeck?.id
    let episodeID = episodeID ?? onDeckID
    guard let episodeID else { return }

    do {
      try await repo.markFinished(episodeID)
    } catch {
      Self.log.caughtError("finishEpisode: failed to mark episode \(episodeID) finished", error)
    }

    guard episodeID == onDeckID
    else { return }

    temporarilyHaltSeekCommands()
    await clearOnDeck()

    // Automatically load and play the next episode if one exists
    do {
      if let nextEpisode = try await queue.nextEpisode {
        Self.log.debug("next episode exists to automatically load: \(nextEpisode.toString)")

        try await load(nextEpisode)
        await play()
      } else {
        Self.log.debug("no next episode, stopping")
        await setStatus(.stopped)
      }
    } catch {
      Self.log.caughtError("finishEpisode: failed to load next episode after \(episodeID)", error)
      await alert(ErrorKit.message(for: error))
    }
  }

  // MARK: - Seeking

  func seekForward(_ interval: TimeInterval? = nil) async {
    let duration = interval ?? userSettings.skipForwardInterval
    await podAVPlayer.seekForward(CMTime.seconds(duration))
  }

  func seekBackward(_ interval: TimeInterval? = nil) async {
    let duration = interval ?? userSettings.skipBackwardInterval
    await podAVPlayer.seekBackward(CMTime.seconds(duration))
  }

  func seek(to time: CMTime) async {
    await podAVPlayer.seek(to: time)
  }

  // Incoming command from user input (in contrast to setPlaybackRate(_))
  func setRate(_ rate: Float) async {
    Assert.precondition(rate > 0, "Setting playback rate to 0?")

    sharedState.setPlayRate(rate)
    await podAVPlayer.setRate(rate)
  }

  // MARK: - Private State Management

  private func setOnDeck(_ podcastEpisode: PodcastEpisode) async throws {
    Self.log.debug("setOnDeck: \(podcastEpisode.toString)")

    NowPlayingInfo.setOnDeck(podcastEpisode)
    stateManager.setOnDeck(podcastEpisode)
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
      await setCurrentTime(.zero)
    }
  }

  private func fetchImage(for podcastEpisode: PodcastEpisode) {
    imageFetchTask?.cancel()

    imageFetchTask = Task {
      [weak self, episodeID = podcastEpisode.id, imageURL = podcastEpisode.image] in
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

  private func clearOnDeck() async {
    Self.log.debug("clearOnDeck: executing")
    imageFetchTask?.cancel()
    await podAVPlayer.clear()
    NowPlayingInfo.clear()
    stateManager.clearOnDeck()
  }

  private func handlePlaybackFailure() async {
    Self.log.info("handlePlaybackFailure: recovering from AVPlayerItem failure")

    guard let episodeID = sharedState.onDeck?.id else {
      Self.log.warning("handlePlaybackFailure: no episode on deck to recover")
      return
    }

    await podAVPlayer.savePosition()
    await logFailureDiagnostics(episodeID)
    await stop()

    // Attempt auto-recovery unless we just tried for this same episode
    let shouldAttemptRecovery: Bool
    if let lastRecoveryAttempt,
      lastRecoveryAttempt.episodeID == episodeID,
      Date().timeIntervalSince(lastRecoveryAttempt.time) < recoveryDebounceInterval
    {
      shouldAttemptRecovery = false
    } else {
      shouldAttemptRecovery = true
    }

    if shouldAttemptRecovery {
      lastRecoveryAttempt = (episodeID, Date())
      do {
        guard let podcastEpisode = try await repo.podcastEpisode(episodeID) else {
          Self.log.warning("handlePlaybackFailure: episode \(episodeID) no longer exists")
          return
        }

        Self.log.info(
          "handlePlaybackFailure: attempting auto-recovery for \(podcastEpisode.toString)"
        )
        try await load(podcastEpisode)
        await play()
        Self.log.info("handlePlaybackFailure: auto-recovery succeeded")
        return
      } catch {
        Self.log.caughtError(
          "handlePlaybackFailure: auto-recovery failed",
          error,
          remarkable: .warning
        )
      }
    } else {
      Self.log.warning(
        "handlePlaybackFailure: skipping auto-recovery, already attempted for \(episodeID)"
      )
    }

    // Fall back to returning episode to queue
    do {
      try await queue.unshift(episodeID)
    } catch {
      Self.log.caughtError(
        "handlePlaybackFailure: failed to return episode \(episodeID) to queue",
        error
      )
    }

    await alert("Playback failed unexpectedly. The episode has been returned to your queue.")
  }

  private func logFailureDiagnostics(_ episodeID: Episode.ID) async {
    // Check cached file integrity
    let podcastEpisode: PodcastEpisode?
    do {
      podcastEpisode = try await repo.podcastEpisode(episodeID)
    } catch {
      Self.log.caughtError(
        "logFailureDiagnostics: failed to fetch episode \(episodeID)",
        error
      )
      podcastEpisode = nil
    }

    if let podcastEpisode, let cachedURL = podcastEpisode.episode.cachedURL {
      if fileManager.fileExists(at: cachedURL.rawValue) {
        let size: Int64
        do {
          size = try fileManager.fileSize(for: cachedURL.rawValue)
          Self.log.info("logFailureDiagnostics: cached file exists, size: \(size) bytes")
        } catch {
          size = -1
          Self.log.caughtError(
            "logFailureDiagnostics: failed to get file size at \(cachedURL)",
            error
          )
        }
      } else {
        Self.log.warning("logFailureDiagnostics: cached file MISSING at \(cachedURL)")
      }
    } else {
      Self.log.info("logFailureDiagnostics: episode not cached")
    }

    // Log audio session state
    let session = AVAudioSession.sharedInstance()
    Self.log.info(
      """
      logFailureDiagnostics: audio session state
        category: \(session.category.rawValue)
        mode: \(session.mode.rawValue)
        isOtherAudioPlaying: \(session.isOtherAudioPlaying)
        currentRoute: \(session.currentRoute.outputs.map(\.portType.rawValue))
      """
    )
  }

  private func setStatus(_ status: PlaybackStatus) async {
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

  private func setCurrentTime(_ currentTime: CMTime) async {
    Self.log.trace("setCurrentTime: \(currentTime)")
    NowPlayingInfo.setCurrentTime(currentTime)
    stateManager.setCurrentTime(currentTime)
  }

  // Incoming state update from the AVPlayer (in contrast to setRate(_))
  private func setPlaybackRate(_ rate: Float) async {
    Self.log.debug("setPlaybackRate: \(rate)")
    NowPlayingInfo.setPlaybackRate(rate)
    sharedState.setPlayRate(rate)
  }

  private func temporarilyHaltSeekCommands() {
    restartSeekCommandsTask?.cancel()
    ignoreSeekCommands = true
    restartSeekCommandsTask = Task { [weak self] in
      guard let self else { return }

      try await sleeper.sleep(for: seekIgnoreTime)
      try Task.checkCancellation()
      ignoreSeekCommands = false
    }
  }

  // MARK: - Private Change Handlers

  private func handleItemStatusChange(status: AVPlayerItem.Status, episodeID: Episode.ID) async {
    Self.log.debug("handleItemStatusChange: \(status) for episode \(episodeID)")

    if status == .failed {
      Self.log.warning("status is failed for \(episodeID), clearing on deck and unshifting")
      await stop()
      do {
        try await queue.unshift(episodeID)
      } catch {
        Self.log.caughtError(
          "handleItemStatusChange: failed to unshift episode \(episodeID) after status failure",
          error
        )
      }
    }
  }

  private func handleDidPlayToEnd(_ episodeID: Episode.ID) async {
    Self.log.debug("handleDidPlayToEnd: \(episodeID)")

    await finishEpisode(episodeID)
  }

  private func handleTrackBehaviorChange() {
    Self.log.debug(
      """
      handleTrackBehaviorChange:
        queueCount: \(sharedState.queueCount)
        onDeck: \(String(describing: sharedState.onDeck?.toString))
        nextTrackBehavior: \(userSettings.nextTrackBehavior)
      """
    )

    CommandCenter.updateNextTrack()
    NowPlayingInfo.updateQueueCount()
  }

  private func handleDefaultPlaybackRateChange() {
    Self.log.debug(
      """
      handleDefaultPlaybackRateChange:
        defaultPlaybackRate: \(userSettings.defaultPlaybackRate)
      """
    )

    NowPlayingInfo.updateDefaultPlaybackRate()
  }

  private func handleSkipIntervalsChange() {
    Self.log.debug(
      """
      handleSkipIntervalsChange:
        skipForwardInterval: \(userSettings.skipForwardInterval)
        skipBackwardInterval: \(userSettings.skipBackwardInterval)
      """
    )

    CommandCenter.updateSkipIntervals()
  }

  private func handleMediaServicesReset() async {
    Self.log.info("handleMediaServicesReset: beginning recovery process")

    guard configureAudioSession() else { return }
    Self.log.debug("handleMediaServicesReset: audio session configured")

    // Force creation of new instances since the old ones are invalid after media services reset
    Container.shared.avPlayer.reset(.scope)
    Self.log.debug("handleMediaServicesReset: reset AVPlayer scope")

    Container.shared.mpRemoteCommandCenter.reset(.scope)
    Self.log.debug("handleMediaServicesReset: reset mpRemoteCommandCenter scope")

    Container.shared.mpNowPlayingInfoCenter.reset(.scope)
    Self.log.debug("handleMediaServicesReset: reset mpNowPlayingInfoCenter scope")

    // Re-register on the fresh factory instances
    CommandCenter.registerRemoteCommandHandlers()
    Self.log.debug("handleMediaServicesReset: remote command handlers re-registered")

    let currentOnDeck = sharedState.onDeck
    await clearOnDeck()
    Self.log.debug("handleMediaServicesReset: cleared existing playback state")

    do {
      let episodeToLoad: PodcastEpisode?
      if let currentOnDeck {
        Self.log.debug("handleMediaServicesReset: recovering on-deck episode \(currentOnDeck.id)")
        episodeToLoad = try await repo.podcastEpisode(currentOnDeck.id)
      } else if let nextEpisode = try await queue.nextEpisode {
        Self.log.debug(
          """
          handleMediaServicesReset: no on-deck episode, \
          falling back to top of queue: \(nextEpisode.toString)
          """
        )
        episodeToLoad = nextEpisode
      } else {
        episodeToLoad = nil
      }

      guard let episodeToLoad else {
        Self.log.debug("handleMediaServicesReset: no episode to recover")
        return
      }

      Self.log.info("handleMediaServicesReset: reloading \(episodeToLoad.toString)")
      try await load(episodeToLoad)
      Self.log.info("handleMediaServicesReset: recovery finished successfully")
    } catch {
      Self.log.caughtError(
        "handleMediaServicesReset: failed to recover playback",
        error
      )
    }
  }

  // MARK: - Notification Tracking

  private nonisolated func notificationTracking() {
    Assert.neverCalled()

    Task { @PlayActor [weak self] in
      guard let self else { return }
      for await notification in notifications(AVAudioSession.interruptionNotification) {
        let parsedNotification = AudioInterruption.parse(notification)
        Self.log.debug("Got audio interruption notification: \(parsedNotification)")

        switch parsedNotification {
        case .pause:
          await pause()
        case .resume:
          await play()
        case .ignore:
          break
        }
      }
    }

    Task { @PlayActor [weak self] in
      guard let self else { return }
      for await _ in notifications(AVAudioSession.mediaServicesWereResetNotification) {
        await handleMediaServicesReset()
      }
    }

    Task { @PlayActor [weak self] in
      guard let self else { return }
      for await notification in notifications(AVAudioSession.routeChangeNotification) {
        guard
          let reasonValue = notification.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt,
          let reason = AVAudioSession.RouteChangeReason(rawValue: reasonValue)
        else { continue }

        let session = AVAudioSession.sharedInstance()
        Self.log.info(
          """
          Audio route changed
            reason: \(reason)
            outputs: \(session.currentRoute.outputs.map(\.portType.rawValue))
          """
        )
      }
    }

    Task { @PlayActor [weak self] in
      guard let self else { return }
      for await notification in notifications(AVPlayerItem.failedToPlayToEndTimeNotification) {
        guard await podAVPlayer.isCurrentItem(notification.object as? AVPlayerItem) else {
          Self.log.warning("Ignoring failedToPlayToEndTimeNotification from non-current item")
          continue
        }

        guard
          let error = notification.userInfo?[AVPlayerItemFailedToPlayToEndTimeErrorKey]
            as? any Error
        else { Assert.fatal("failedToPlayToEndTimeNotification: \(notification) is invalid") }

        Self.log.caughtError(
          "AVPlayerItem failed to play to end time",
          error,
          remarkable: .warning
        )

        await handlePlaybackFailure()
      }
    }

    Task { @PlayActor [weak self] in
      guard let self else { return }
      for await notification in notifications(AVPlayerItem.playbackStalledNotification) {
        guard await podAVPlayer.isCurrentItem(notification.object as? AVPlayerItem) else {
          Self.log.warning("Ignoring playbackStalledNotification from non-current item")
          continue
        }
        Self.log.warning("AVPlayerItem playback stalled")
      }
    }

    Task { @PlayActor [weak self] in
      guard let self else { return }
      for await notification in notifications(AVPlayerItem.newErrorLogEntryNotification) {
        guard let item = notification.object as? AVPlayerItem
        else { Assert.fatal("newErrorLogEntryNotification: \(notification) is invalid") }

        guard await podAVPlayer.isCurrentItem(item) else {
          Self.log.warning("Ignoring newErrorLogEntryNotification from non-current item")
          continue
        }

        guard let errorLog = item.errorLog()
        else { Assert.fatal("newErrorLogEntryNotification fired but errorLog() returned nil?") }

        Self.log.error(
          """
          Error log events for episode \
            \(String(describing: sharedState.onDeck?.id)) (\(errorLog.events.count)):
            \(errorLog.events.map { event in
              String(describing: event.errorComment)
            }.joined(separator: "\n  "))
          """
        )
      }
    }
  }

  // MARK: - Subordinate Async Streams

  private nonisolated func asyncStreams() {
    Assert.neverCalled()

    // CommandCenter

    Task { @PlayActor [weak self] in
      guard let self else { return }
      for await command in commandCenterStream.stream {
        switch command {
        case .play:
          await play()
        case .pause:
          await pause()
        case .togglePlayPause:
          await toggle()
        case .skipForward(let interval):
          await seekForward(interval)
        case .skipBackward(let interval):
          await seekBackward(interval)
        case .playbackPosition(let position):
          if ignoreSeekCommands {
            Self.log.debug("playManager: ignoring seek to \(position)")
            continue
          }
          await seek(to: CMTime.seconds(position))
        case .changePlaybackRate(let rate):
          await setRate(rate)
        case .nextEpisode:
          switch userSettings.nextTrackBehavior {
          case .nextEpisode:
            await finishEpisode()
          case .skipInterval:
            await seekForward()
          }
        case .previousEpisode:
          await seekBackward()
        }
      }
    }

    // PodAVPlayer

    Task { @PlayActor [weak self] in
      guard let self else { return }
      for await (status, episodeID) in await podAVPlayer.itemStatusStream {
        await handleItemStatusChange(status: status, episodeID: episodeID)
      }
    }

    Task { @PlayActor [weak self] in
      guard let self else { return }
      for await currentTime in await podAVPlayer.currentTimeStream {
        await setCurrentTime(currentTime)
      }
    }

    Task { @PlayActor [weak self] in
      guard let self else { return }
      for await rate in await podAVPlayer.rateStream {
        await setPlaybackRate(rate)
      }
    }

    Task { @PlayActor [weak self] in
      guard let self else { return }
      for await controlStatus in await podAVPlayer.controlStatusStream {
        Self.log.debug("AVPlayer timeControlStatus changed to: \(controlStatus)")
        switch controlStatus {
        case .paused:
          await setStatus(.paused)
        case .playing:
          await setStatus(.playing)
        case .waiting:
          await setStatus(.waiting)
        case .loading(_), .stopped:
          Assert.fatal("\(controlStatus) from PodAVPlayer?")
        }
      }
    }

    Task { @PlayActor [weak self] in
      guard let self else { return }
      for await episodeID in await podAVPlayer.didPlayToEndStream {
        await handleDidPlayToEnd(episodeID)
      }
    }

    // UserSettings

    Task { @PlayActor [weak self] in
      guard let self else { return }
      for await _ in userSettings.$nextTrackBehavior.stream() {
        Self.log.debug("nextTrackBehavior changed")
        handleTrackBehaviorChange()
      }
    }

    Task { @PlayActor [weak self] in
      guard let self else { return }
      for await _ in userSettings.$defaultPlaybackRate.stream() {
        Self.log.debug("defaultPlaybackRate changed")
        handleDefaultPlaybackRateChange()
      }
    }

    Task { @PlayActor [weak self] in
      guard let self else { return }
      for await _ in userSettings.$skipForwardInterval.stream() {
        Self.log.debug("skipForwardInterval changed")
        handleSkipIntervalsChange()
      }
    }

    Task { @PlayActor [weak self] in
      guard let self else { return }
      for await _ in userSettings.$skipBackwardInterval.stream() {
        Self.log.debug("skipBackwardInterval changed")
        handleSkipIntervalsChange()
      }
    }

    // SharedState

    Task { @PlayActor [weak self] in
      guard let self else { return }
      for await _ in sharedState.$queuedPodcastEpisodes.stream() {
        Self.log.debug("queue changed")
        handleTrackBehaviorChange()
      }
    }
  }
}
