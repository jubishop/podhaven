// Copyright Justin Bishop, 2025

import AVFoundation
import FactoryKit
import Foundation
import GRDB
import Logging
import Semaphore
import Sharing
import SwiftUI

extension Container {
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
  @DynamicInjected(\.commandCenter) private var commandCenter
  @DynamicInjected(\.notifications) private var notifications
  @DynamicInjected(\.queue) private var queue
  @DynamicInjected(\.repo) private var repo
  @DynamicInjected(\.sleeper) private var sleeper

  private var alert: Alert { get async { await Container.shared.alert() } }
  nonisolated private var imageFetcher: any ImageFetchable { Container.shared.imageFetcher() }
  private var playState: PlayState { get async { await Container.shared.playState() } }
  private var podAVPlayer: PodAVPlayer { get async { await Container.shared.podAVPlayer() } }

  private static let log = Log.as(LogSubsystem.Play.manager)

  // MARK: - AppStorage

  @WrappedShared(
    Shared<Int?>(.appStorage("PlayManager-currentEpisodeID")),
    get: {
      guard let currentEpisodeInt = $0, let currentEpisodeInt64 = Int64(exactly: currentEpisodeInt)
      else { return nil }

      return Episode.ID(rawValue: currentEpisodeInt64)
    },
    set: {
      guard let newEpisodeID = $0
      else { return nil }

      return Int(exactly: newEpisodeID.rawValue)
    }
  )
  private var currentEpisodeID: Episode.ID? {
    willSet {
      Self.log.debug("Setting currentEpisodeID to \(String(describing: newValue))")
    }
  }

  // MARK: - State Management

  private var nowPlayingInfo: NowPlayingInfo? {
    willSet {
      if newValue == nil { nowPlayingInfo?.clear() }
    }
  }
  private var loadTask: Task<Bool, any Error>?

  // MARK: - Initialization

  fileprivate init() {}

  func start() async {
    Assert.neverCalled()

    notificationTracking()
    asyncStreams()

    if let currentEpisodeID {
      let podcastEpisode: PodcastEpisode?
      do {
        podcastEpisode = try await repo.episode(currentEpisodeID)
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
    let outgoing = await playState.onDeck

    if let outgoing, outgoing == incoming {
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
        try await setOnDeck(try await podAVPlayer.load(incoming))
      } catch {
        await Task { [weak self] in  // Task to execute even inside cancellation
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
    let nowOnDeck = await playState.onDeck

    Self.log.debug(
      """
      cleanUpAfterLoadFailure
        outgoing: \(String(describing: outgoing?.toString))
        incoming: \(incoming.toString)
        nowOnDeck: \(String(describing: nowOnDeck?.toString))
      """
    )

    // Put the outgoing episode back if we displaced it
    if let outgoing, outgoing != nowOnDeck {
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
      if Self.log.shouldLog(.debug) {
        Self.log.debug(
          """
          cleanUpAfterLoadFailure: no stopping after load failure because new podcast seems \
          to have loaded
            Failed to load: \(String(describing: incoming.toString)) \
            Loaded instead: \(nowOnDeck)
          """
        )
      }
    } else {
      await clearOnDeck()
      await setStatus(.stopped)
    }
  }

  // MARK: - Playback Controls

  func play() async {
    await podAVPlayer.play()
  }

  func pause() async {
    await podAVPlayer.pause()
  }

  func toggle() async {
    await podAVPlayer.toggle()
  }

  // MARK: - Seeking

  func seekForward(_ duration: CMTime) async {
    await podAVPlayer.seekForward(duration)
  }

  func seekBackward(_ duration: CMTime) async {
    await podAVPlayer.seekBackward(duration)
  }

  func seek(to time: CMTime) async {
    await podAVPlayer.seek(to: time)
  }

  // MARK: - Private State Management

  private func setOnDeck(_ podcastEpisode: PodcastEpisode) async throws {
    Self.log.debug("setOnDeck: \(podcastEpisode.toString)")

    let onDeck = await OnDeck(
      episodeID: podcastEpisode.id,
      feedURL: podcastEpisode.podcast.feedURL,
      guid: podcastEpisode.episode.guid,
      podcastTitle: podcastEpisode.podcast.title,
      podcastURL: podcastEpisode.podcast.link,
      episodeTitle: podcastEpisode.episode.title,
      duration: podcastEpisode.episode.duration,
      image: {
        do {
          return try await imageFetcher.fetch(podcastEpisode.image)
        } catch {
          Self.log.error(error)
          return nil
        }
      }(),
      media: podcastEpisode.episode.media,
      pubDate: podcastEpisode.episode.pubDate
    )
    try Task.checkCancellation()

    nowPlayingInfo = NowPlayingInfo(onDeck)
    await playState.setOnDeck(onDeck)

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

  private func clearOnDeck() async {
    Self.log.debug("clearOnDeck: executing")
    await podAVPlayer.clear()
    nowPlayingInfo = nil
    await playState.setOnDeck(nil)
  }

  private func setStatus(_ status: PlaybackStatus) async {
    let currentStatus = await playState.status
    if currentStatus.stopped && !status.loading {
      Self.log.debug("setStatus: ignoring \(status) while stopped")
      return
    }

    Self.log.debug("setStatus: \(status)")
    nowPlayingInfo?.playing(status.playing)
    await playState.setStatus(status)
  }

  private func setCurrentTime(_ currentTime: CMTime) async {
    Self.log.trace("setCurrentTime: \(currentTime)")

    nowPlayingInfo?.setCurrentTime(currentTime)
    await playState.setCurrentTime(currentTime)
  }

  // MARK: - Private Change Handlers

  private func handleItemStatusChange(status: AVPlayerItem.Status, podcastEpisode: PodcastEpisode)
    async
  {
    Self.log.debug(
      """
      handleItemStatusChange
        status: \(status)
        podcastEpisode: \(podcastEpisode.toString)
      """
    )

    if status == .failed {
      await clearOnDeck()
      do {
        try await queue.unshift(podcastEpisode.id)
      } catch {
        Self.log.error(error)
      }
    }
  }

  private func handleDidPlayToEnd(_ podcastEpisode: PodcastEpisode) async throws {
    Self.log.debug("handleDidPlayToEnd: \(podcastEpisode.toString)")

    await clearOnDeck()

    do {
      try await repo.markComplete(podcastEpisode.id)
    } catch {
      Self.log.error(error)
    }

    do {
      try await cacheManager.clearCache(for: podcastEpisode.episode)
    } catch {
      Self.log.error(error)
    }

    // Automatically load and play the next episode if one exists
    if let nextEpisode = try await queue.nextEpisode {
      Self.log.debug(
        """
        handleDidPlayToEnd: next episode exists to automatically load
          \(nextEpisode.toString)
        """
      )

      do {
        try await load(nextEpisode)
        await play()
      } catch {
        Self.log.error(error)
        await alert("Failed to load next episode: \(nextEpisode.episode.title)")
        return
      }
    } else {
      Self.log.debug("handleDidPlayToEnd: no next episode, stopping")
      await clearOnDeck()
      await setStatus(.stopped)
    }
  }

  // MARK: - Notification Tracking

  private func notificationTracking() {
    Assert.neverCalled()

    Task { [weak self] in
      guard let self else { return }
      for await notification in notifications(AVAudioSession.interruptionNotification) {
        switch AudioInterruption.parse(notification) {
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
        Self.log.critical("Media services were reset - this could cause playback to stop")
        await alert(
          """
          Media services were reset, this has been reported.
          You will have to restart the app.
          """
        )
      }
    }

    Task { [weak self] in
      guard let self else { return }
      for await notification in notifications(AVPlayerItem.failedToPlayToEndTimeNotification) {
        guard
          let error = notification.userInfo?[AVPlayerItemFailedToPlayToEndTimeErrorKey] as? Error
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

    Task { [weak self] in
      guard let self else { return }
      for await command in commandCenter.stream {
        switch command {
        case .play:
          await play()
        case .pause:
          await pause()
        case .togglePlayPause:
          await toggle()
        case .skipForward(let interval):
          await seekForward(CMTime.seconds(interval))
        case .skipBackward(let interval):
          await seekBackward(CMTime.seconds(interval))
        case .playbackPosition(let position):
          await seek(to: CMTime.seconds(position))
        }
      }
    }

    Task { [weak self] in
      guard let self else { return }
      for await (status, podcastEpisode) in await podAVPlayer.itemStatusStream {
        await self.handleItemStatusChange(status: status, podcastEpisode: podcastEpisode)
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
        Self.log.debug("Current rate changed to: \(rate)")
      }
    }

    Task { [weak self] in
      guard let self else { return }
      for await controlStatus in await podAVPlayer.controlStatusStream {
        Self.log.debug("Control status changed to: \(controlStatus)")
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
      for await podcastEpisode in await podAVPlayer.didPlayToEndStream {
        do {
          try await handleDidPlayToEnd(podcastEpisode)
        } catch {
          Self.log.error(error)
          await alert(ErrorKit.message(for: error))
        }
      }
    }
  }
}
