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
  @DynamicInjected(\.commandCenterStream) var commandCenterStream
  @DynamicInjected(\.fileManager) var fileManager
  @DynamicInjected(\.imagePipeline) private var imagePipeline
  @DynamicInjected(\.notifications) var notifications
  @DynamicInjected(\.observatory) private var observatory
  @DynamicInjected(\.queue) var queue
  @DynamicInjected(\.repo) var repo
  @DynamicInjected(\.sharedState) var sharedState
  @DynamicInjected(\.stateManager) private var stateManager
  @DynamicInjected(\.userSettings) var userSettings

  var alert: Alert { get async { await Container.shared.alert() } }
  var podAVPlayer: PodAVPlayer { get async { await Container.shared.podAVPlayer() } }

  nonisolated static let log = Log.as(LogSubsystem.Play.manager)

  // MARK: - Configurable Constants

  let recoveryDebounceInterval: TimeInterval = 5

  // MARK: - State Management

  var lastRecoveryAttempt: (episodeID: Episode.ID, time: Date)?
  private var imageFetchTask: Task<Void, Never>?
  private var loadTask: Task<Bool, any Error>?
  private let startOnce = AsyncOnce()
  private let startStreamConsumersOnce = Once()
  private(set) var ignoreRemoteScrubCommands = false
  private var lastLoggedTime = Date.distantPast

  // MARK: - Initialization

  fileprivate init() {}

  // Starts the async stream consumers for command center and notifications.
  // Called from AppDelegate after audio session and command handlers are configured.
  nonisolated func startStreamConsumers() {
    startStreamConsumersOnce.run {
      Self.log.debug("startStreamConsumers: executing")

      notificationTracking()
      asyncStreams()
    }
  }

  // Full startup for foreground use (called when app becomes active).
  // Loads the current episode if one exists.
  // Note: Audio session and command handlers must already be configured.
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
          Button("Send Report and Crash") { [error] in
            Assert.fatal("Failed to initialize the audio session: \(error)")
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

      guard configureAudioSession() else { return false }

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

    ignoreRemoteScrubCommands = true
    defer { ignoreRemoteScrubCommands = false }

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

  func clearOnDeck() async {
    Self.log.debug("clearOnDeck: executing")
    imageFetchTask?.cancel()
    await podAVPlayer.clear()
    NowPlayingInfo.clear()
    stateManager.clearOnDeck()
  }

  func setCurrentTime(_ currentTime: CMTime) async {
    let now = Date()
    if now.timeIntervalSince(lastLoggedTime) >= 10 {
      lastLoggedTime = now
      Self.log.debug("setCurrentTime: \(currentTime)")
    }
    NowPlayingInfo.setCurrentTime(currentTime)
    stateManager.setCurrentTime(currentTime)
  }

  func setStatus(_ status: PlaybackStatus) async {
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
  func setPlaybackRate(_ rate: Float) async {
    Self.log.debug("setPlaybackRate: \(rate)")
    NowPlayingInfo.setPlaybackRate(rate)
    sharedState.setPlayRate(rate)
  }
}
