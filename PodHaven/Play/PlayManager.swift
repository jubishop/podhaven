// Copyright Justin Bishop, 2025

import AVFoundation
import Combine
import FactoryKit
import Foundation
import GRDB
import Logging
import Nuke
import Sharing
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

  private static let log = Log.as(LogSubsystem.Play.manager)

  // MARK: - AppStorage

  @Shared(.appStorage("PlayManager-currentEpisodeID"))
  private var storedCurrentEpisodeID: Int?

  private var currentEpisodeID: Episode.ID? {
    get {
      guard let currentEpisodeInt = storedCurrentEpisodeID,
        let currentEpisodeInt64 = Int64(exactly: currentEpisodeInt)
      else { return nil }

      return Episode.ID(rawValue: currentEpisodeInt64)
    }
    set {
      Self.log.debug("Setting currentEpisodeID to \(String(describing: newValue))")
      $storedCurrentEpisodeID.withLock { stored in
        guard let newEpisodeID = newValue
        else {
          stored = nil
          return
        }

        stored = Int(exactly: newEpisodeID.rawValue)
      }
    }
  }

  // MARK: - Configurable Constants

  let seekIgnoreTime: Duration = .seconds(1)

  // MARK: - State Management

  private var imageFetchTask: Task<Void, Never>?
  private var loadTask: Task<Bool, any Error>?
  private var restartSeekCommandsTask: Task<Void, any Error>?
  private var ignoreSeekCommands = false

  // MARK: - Initialization

  fileprivate init() {}

  func start() async {
    guard Function.neverCalled() else { return }

    Self.log.debug("start: executing")

    guard configureAudioSession() else { return }

    CommandCenter.registerRemoteCommandHandlers()

    notificationTracking()
    asyncStreams()

    guard let currentEpisodeID else { return }

    let podcastEpisode: PodcastEpisode?
    do {
      podcastEpisode = try await repo.podcastEpisode(currentEpisodeID)
    } catch {
      await alert("Podcast episode with id: \"\(currentEpisodeID)\" not found")
      Self.log.error(error)
      return
    }

    if let podcastEpisode {
      do {
        try await load(podcastEpisode)
      } catch {
        await alert("Failed to load podcast episode \(podcastEpisode.episode.title)")
        Self.log.error(error)
      }
    }
  }

  func configureAudioSession() -> Bool {
    Self.log.info("configureAudioSession: executing")
    do {
      try Container.shared.configureAudioSession()()
    } catch {
      Self.log.error(error)
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
  func load(_ podcastEpisode: PodcastEpisode) async throws(PlaybackError) -> Bool {
    loadTask?.cancel()

    return try await PlaybackError.catch {
      try await performLoad(podcastEpisode)
    }
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
        try Container.shared.setAudioSessionActive()(true)
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
      Self.log.error(error)
    }

    // If there was an outgoing episode, put it back at the front of the queue
    if let outgoing {
      Self.log.debug("cleanUpAfterLoadSuccess: unshifting outgoing episode: \(outgoing.toString)")
      do {
        try await queue.unshift(outgoing.id)
      } catch {
        Self.log.error(error)
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
        Self.log.error(error)
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
        Self.log.error(error)
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
      Self.log.error(error)
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
      Self.log.error(error)
      await alert(ErrorKit.coreMessage(for: error))
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

    currentEpisodeID = podcastEpisode.id
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
        Self.log.error(error)
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

  private func setStatus(_ status: PlaybackStatus) async {
    Self.log.debug("setStatus: \(status)")
    sharedState.setPlaybackStatus(status)

    if status == .stopped {
      do {
        try Container.shared.setAudioSessionActive()(false)
      } catch {
        Self.log.error(error)
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

  private func handleItemStatusChange(status: AVPlayerItem.Status, episodeID: Episode.ID)
    async
  {
    Self.log.debug(
      """
      handleItemStatusChange
        status: \(status)
        episodeID: \(episodeID)
      """
    )

    if status == .failed {
      Self.log.debug(
        "handleItemStatusChange: failed for \(episodeID), clearing on deck and unshifting"
      )
      await stop()
      do {
        try await queue.unshift(episodeID)
      } catch {
        Self.log.error(error)
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

    CommandCenter.registerRemoteCommandHandlers()
    Self.log.debug("handleMediaServicesReset: remote command handlers re-registered")

    let currentOnDeck = sharedState.onDeck
    await clearOnDeck()
    Self.log.debug("handleMediaServicesReset: cleared existing playback state")

    // Force creation of a new AVPlayer instance since the old one is invalid
    Container.shared.avPlayer.reset(.scope)
    Self.log.debug("handleMediaServicesReset: reset AVPlayer scope")

    Self.log.debug(
      """
      handleMediaServicesReset: captured state:
        currentOnDeck: \(String(describing: currentOnDeck?.toString))
      """
    )

    if let currentOnDeck {
      do {
        guard let podcastEpisode = try await repo.podcastEpisode(currentOnDeck.id)
        else {
          Self.log.warning(
            "handleMediaServicesReset: episode \(currentOnDeck.id) no longer exists"
          )
          await setStatus(.stopped)
          return
        }

        Self.log.info("handleMediaServicesReset: reloading \(podcastEpisode.toString)")
        try await load(podcastEpisode)

        Self.log.info("handleMediaServicesReset: recovery finished successfully")
      } catch {
        Self.log.error(error)

        await alert(
          """
          Playback was interrupted by a system issue and couldn't be restored automatically. \
          The episode has been put back in your queue.
          """
        )
      }
    } else {
      Self.log.debug("handleMediaServicesReset: no episode was playing, recovery not needed")
    }
  }

  // MARK: - Notification Tracking

  private func notificationTracking() {
    Assert.neverCalled()

    Task { [weak self] in
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

    Task { [weak self] in
      guard let self else { return }
      for await _ in notifications(AVAudioSession.mediaServicesWereResetNotification) {
        await handleMediaServicesReset()
      }
    }

    Task { [weak self] in
      guard let self else { return }
      for await notification in notifications(AVPlayerItem.failedToPlayToEndTimeNotification) {
        guard
          let error = notification.userInfo?[AVPlayerItemFailedToPlayToEndTimeErrorKey]
            as? any Error
        else { Assert.fatal("failedToPlayToEndTimeNotification: \(notification) is invalid") }

        Self.log.warning(
          """
          AVPlayerItem failed to play to end time
          \(ErrorKit.loggableMessage(for: error))
          """
        )
      }
    }

    Task { [weak self] in
      guard let self else { return }
      for await _ in notifications(AVPlayerItem.playbackStalledNotification) {
        Self.log.warning("AVPlayerItem playback stalled")
      }
    }

    Task { [weak self] in
      guard let self else { return }
      for await notification in notifications(AVPlayerItem.newErrorLogEntryNotification) {
        guard let item = notification.object as? AVPlayerItem
        else { Assert.fatal("newErrorLogEntryNotification: \(notification) is invalid") }

        guard let errorLog = item.errorLog()
        else { Assert.fatal("newErrorLogEntryNotification fired but errorLog() returned nil?") }

        Self.log.error(
          """
          Error log events (\(errorLog.events.count)):
            \(errorLog.events.map { event in
              String(describing: event.errorComment)
            }.joined(separator: "\n  "))
          """
        )
      }
    }
  }

  // MARK: - Subordinate Async Streams

  private func asyncStreams() {
    Assert.neverCalled()

    // CommandCenter

    Task { [weak self] in
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

    Task { [weak self] in
      guard let self else { return }
      for await (status, episodeID) in await podAVPlayer.itemStatusStream {
        await handleItemStatusChange(status: status, episodeID: episodeID)
      }
    }

    Task { [weak self] in
      guard let self else { return }
      for await currentTime in await podAVPlayer.currentTimeStream {
        await setCurrentTime(currentTime)
      }
    }

    Task { [weak self] in
      guard let self else { return }
      for await rate in await podAVPlayer.rateStream {
        await setPlaybackRate(rate)
      }
    }

    Task { [weak self] in
      guard let self else { return }
      for await controlStatus in await podAVPlayer.controlStatusStream {
        Self.log.trace("Control status changed to: \(controlStatus)")
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

    Task { [weak self] in
      guard let self else { return }
      for await episodeID in await podAVPlayer.didPlayToEndStream {
        await handleDidPlayToEnd(episodeID)
      }
    }

    // UserSettings

    Task { [weak self] in
      guard let self else { return }
      for await _ in userSettings.$nextTrackBehavior.publisher.values {
        Self.log.debug("nextTrackBehavior changed")
        handleTrackBehaviorChange()
      }
    }

    Task { [weak self] in
      guard let self else { return }
      for await _ in userSettings.$defaultPlaybackRate.publisher.values {
        Self.log.debug("defaultPlaybackRate changed")
        handleDefaultPlaybackRateChange()
      }
    }

    Task { [weak self] in
      guard let self else { return }
      for await _ in userSettings.$skipForwardInterval.publisher.values {
        Self.log.debug("skipForwardInterval changed")
        handleSkipIntervalsChange()
      }
    }

    Task { [weak self] in
      guard let self else { return }
      for await _ in userSettings.$skipBackwardInterval.publisher.values {
        Self.log.debug("skipBackwardInterval changed")
        handleSkipIntervalsChange()
      }
    }

    // SharedState

    Task { [weak self] in
      guard let self else { return }
      for await _ in sharedState.queuedPodcastEpisodesStream() {
        Self.log.debug("queue changed")
        handleTrackBehaviorChange()
      }
    }
  }
}
