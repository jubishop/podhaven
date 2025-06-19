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
    Factory(self) { PlayManager() }.scope(.cached)
  }
}

actor PlayManager {
  @DynamicInjected(\.commandCenter) private var commandCenter
  @DynamicInjected(\.notifications) private var notifications
  @DynamicInjected(\.queue) private var queue
  @DynamicInjected(\.repo) private var repo

  private var alert: Alert { get async { await Container.shared.alert() } }
  nonisolated private var imageFetcher: any ImageFetchable { Container.shared.imageFetcher() }
  private var playState: PlayState { get async { await Container.shared.playState() } }
  private var podAVPlayer: PodAVPlayer { get async { await Container.shared.podAVPlayer() } }

  private let log = Log.as(LogSubsystem.Play.manager)

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
  private var currentEpisodeID: Episode.ID?

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

    startInterruptionNotifications()
    startPlayToEndTimeNotifications()
    startListeningToCommandCenter()
    startListeningToCurrentItem()
    startListeningToCurrentTime()
    startListeningToControlStatus()

    if let currentEpisodeID {
      do {
        if let podcastEpisode = try await repo.episode(currentEpisodeID) {
          try await load(podcastEpisode)
        }
      } catch {
        log.error(error)
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
      log.debug("performLoad: ignoring \(incoming.toString), already loaded")
      return false
    }

    let task = Task<Bool, any Error> { [weak self] in
      guard let self else { return false }
      log.info("performLoad: \(incoming.toString)")

      await podAVPlayer.removeObservers()
      await setStatus(.loading(incoming.episode.title))
      await pause()
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

      log.debug("performLoad: dequeueing incoming episode: \(incoming.toString)")
      do {
        try await queue.dequeue(incoming.id)
      } catch {
        log.error(error)
      }

      if let outgoing {
        log.debug("performLoad: unshifting outgoing episode: \(outgoing.toString)")
        do {
          try await queue.unshift(outgoing.id)
        } catch {
          log.error(error)
        }
      }

      await podAVPlayer.addObservers()
      return true
    }

    loadTask = task
    return try await task.value
  }

  private func cleanUpAfterLoadFailure(_ outgoing: OnDeck?, _ incoming: PodcastEpisode) async {
    let nowOnDeck = await playState.onDeck

    log.debug(
      """
      cleanUpAfterLoadFailure
        outgoing: \(String(describing: outgoing?.toString))
        incoming: \(incoming.toString)
        nowOnDeck: \(String(describing: nowOnDeck?.toString))
      """
    )

    if let outgoing, outgoing != nowOnDeck {
      log.debug(
        """
        cleanUpAfterLoadFailure: unshifting outgoing episode post failure: \
        \(outgoing.toString)
        """
      )
      do {
        try await queue.unshift(outgoing.id)
      } catch {
        log.error(error)
      }
    }

    if incoming.id != nowOnDeck?.id {
      log.debug(
        """
        cleanUpAfterLoadFailure: unshifting incoming episode post failure: \
        \(incoming.toString)
        """
      )
      do {
        try await queue.unshift(incoming.id)
      } catch {
        log.error(error)
      }
    }

    if let nowOnDeck {
      if log.shouldLog(.debug) {
        log.debug(
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
    log.debug("setOnDeck: \(podcastEpisode.toString)")

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
          log.error(error)
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
      log.debug(
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
    log.debug("clearOnDeck: executing")
    await podAVPlayer.clear()
    nowPlayingInfo = nil
    await playState.setOnDeck(nil)
  }

  private func setStatus(_ status: PlaybackStatus) async {
    log.debug("setStatus: \(status)")
    nowPlayingInfo?.playing(status.playing)
    await playState.setStatus(status)
  }

  private func setCurrentTime(_ currentTime: CMTime) async {
    log.trace("setCurrentTime: \(currentTime)")

    nowPlayingInfo?.setCurrentTime(currentTime)
    await playState.setCurrentTime(currentTime)
  }

  // MARK: - Private Change Handlers

  private func handleCurrentItemChange(_ podcastEpisode: PodcastEpisode?) async throws {
    if let podcastEpisode {
      log.debug("handleCurrentItemChange: \(podcastEpisode.id)")

      do {
        try await queue.dequeue(podcastEpisode.id)
      } catch {
        log.error(error)
      }

      try await setOnDeck(podcastEpisode)
    } else {
      log.debug("handleCurrentItemChange: nil, stopping")

      await clearOnDeck()
      await setStatus(.stopped)

      if let nextEpisode = try await queue.nextEpisode {
        log.debug(
          """
          handleCurrentItemChange: next episode exists to manually load
            \(nextEpisode.toString)
          """
        )
        do {
          try await load(nextEpisode)
        } catch {
          await alert("Failed to load next episode: \(nextEpisode.episode.title)")
          throw error
        }
        await play()
      }
    }
  }

  private func handleDidPlayToEnd(_ mediaURL: MediaURL) async throws {
    guard let podcastEpisode = try await repo.episode(mediaURL)
    else { throw PlaybackError.endedEpisodeNotFound(mediaURL) }

    log.debug("handleDidPlayToEnd: \(podcastEpisode.toString)")
    try await repo.markComplete(podcastEpisode.id)
  }

  // MARK: - Private State Tracking

  private func startInterruptionNotifications() {
    Assert.neverCalled()

    Task { [weak self] in
      guard let self else { return }
      for await notification in await notifications(AVAudioSession.interruptionNotification) {
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
  }

  private func startPlayToEndTimeNotifications() {
    Assert.neverCalled()

    Task { @MainActor [weak self] in
      guard let self else { return }
      for await notification in await notifications(AVPlayerItem.didPlayToEndTimeNotification) {
        guard let playableItem = notification.object as? AVPlayableItem
        else { Assert.fatal("didPlayToEndTimeNotification: object is not an AVPlayableItem") }
        do {
          try await handleDidPlayToEnd(playableItem.assetURL)
        } catch {
          log.error(error)
        }
      }
    }
  }

  private func startListeningToCommandCenter() {
    Assert.neverCalled()

    Task { [weak self] in
      guard let self else { return }
      for await command in await commandCenter.stream {
        switch command {
        case .play:
          await play()
        case .pause:
          await pause()
        case .togglePlayPause:
          await toggle()
        case .skipForward(let interval):
          await seekForward(CMTime.inSeconds(interval))
        case .skipBackward(let interval):
          await seekBackward(CMTime.inSeconds(interval))
        case .playbackPosition(let position):
          await seek(to: CMTime.inSeconds(position))
        }
      }
    }
  }

  private func startListeningToCurrentItem() {
    Assert.neverCalled()

    Task { [weak self] in
      guard let self else { return }
      for await podcastEpisode in await podAVPlayer.currentItemStream {
        do {
          try await handleCurrentItemChange(podcastEpisode)
        } catch {
          log.error(error)
        }
      }
    }
  }

  private func startListeningToCurrentTime() {
    Assert.neverCalled()

    Task { [weak self] in
      guard let self else { return }
      for await currentTime in await podAVPlayer.currentTimeStream {
        await setCurrentTime(currentTime)
      }
    }
  }

  private func startListeningToControlStatus() {
    Assert.neverCalled()

    Task { [weak self] in
      guard let self else { return }
      for await controlStatus in await podAVPlayer.controlStatusStream {
        switch controlStatus {
        case .paused:
          await setStatus(.paused)
        case .playing:
          await setStatus(.playing)
        case .waiting:
          await setStatus(.waiting)
        case .seeking:
          await setStatus(.seeking)
        case .loading(_):
          Assert.fatal("Loading status from PodAVPlayer?")
        case .stopped:
          Assert.fatal("Stopped status from PodAVPlayer?")
        }
      }
    }
  }
}
