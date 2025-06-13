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
  @DynamicInjected(\.images) private var images
  @DynamicInjected(\.notifications) private var notifications
  @DynamicInjected(\.queue) private var queue
  @DynamicInjected(\.repo) private var repo

  var playState: PlayState { get async { await Container.shared.playState() } }
  var podAVPlayer: PodAVPlayer { get async { await Container.shared.podAVPlayer() } }

  private let log = Log.as(LogSubsystem.Play.manager)

  // MARK: - AppStorage

  @WrappedShared(
    Shared<Int?>(.appStorage("currentEpisodeID")),
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
      if newValue == nil {
        log.debug("nowPlayingInfo: nil")
        nowPlayingInfo?.clear()
      }
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
        Log.error(error, from: log)
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

  private func performLoad(_ podcastEpisode: PodcastEpisode) async throws -> Bool {
    let outgoingPodcastEpisode = await podAVPlayer.podcastEpisode

    if outgoingPodcastEpisode?.id == podcastEpisode.id {
      log.trace("performLoad: ignoring \(podcastEpisode.toString), already loaded")
      return false
    }

    let task = Task<Bool, any Error> { [weak self] in
      guard let self else { return false }
      do {
        log.info("performLoad: \(podcastEpisode.toString)")

        await podAVPlayer.removeObservers()
        await pause()
        await setOnDeck(try await podAVPlayer.load(podcastEpisode))

        log.debug("performLoad: dequeueing incoming episode: \(podcastEpisode.toString)")
        do {
          try await queue.dequeue(podcastEpisode.id)
        } catch {
          Log.error(error, from: log)
        }

        if let outgoingPodcastEpisode {
          log.debug("performLoad: unshifting current episode: \(outgoingPodcastEpisode.toString)")
          do {
            try await queue.unshift(outgoingPodcastEpisode.id)
          } catch {
            Log.error(error, from: log)
          }
        }

        await podAVPlayer.addObservers()
        return true
      } catch {
        if let outgoingPodcastEpisode {
          log.debug(
            """
            performLoad: unshifting current episode post failure: \
            \(outgoingPodcastEpisode.toString)
            """
          )
          do {
            try await Task { [weak self] in  // Task to execute even inside cancellation
              guard let self else { return }
              try await queue.unshift(outgoingPodcastEpisode.id)
            }
            .value
          } catch {
            Log.error(error, from: log)
          }
        }

        log.debug(
          """
          performLoad: unshifting incoming episode post failure: \
          \(podcastEpisode.toString)
          """
        )
        do {
          try await Task { [weak self] in  // Task to execute even inside cancellation
            guard let self else { return }
            try await queue.unshift(podcastEpisode.id)
          }
          .value
        } catch {
          Log.error(error, from: log)
        }

        if let newPodcastEpisode = await podAVPlayer.podcastEpisode {
          if log.wouldLog(.debug) {
            log.debug(
              """
              performLoad: no stop() after load failure because new podcast seems to have loaded
                Failed to load: \(String(describing: podcastEpisode.toString)) \
                Loaded instead: \(String(describing: newPodcastEpisode))
              """
            )
          }
        } else {
          await stop()
        }

        throw error
      }
    }

    loadTask = task
    defer { loadTask = nil }

    return try await task.value
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

  private func setOnDeck(_ podcastEpisode: PodcastEpisode) async {
    log.debug("setOnDeck: \(podcastEpisode.toString)")

    let onDeck = await OnDeck(
      feedURL: podcastEpisode.podcast.feedURL,
      guid: podcastEpisode.episode.guid,
      podcastTitle: podcastEpisode.podcast.title,
      podcastURL: podcastEpisode.podcast.link,
      episodeTitle: podcastEpisode.episode.title,
      duration: podcastEpisode.episode.duration,
      image: {
        do {
          return try await images.fetchImage(
            podcastEpisode.episode.image ?? podcastEpisode.podcast.image
          )
        } catch {
          Log.error(error, from: log)
          return nil
        }
      }(),
      media: podcastEpisode.episode.media,
      pubDate: podcastEpisode.episode.pubDate
    )

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

  private func stop() async {
    log.debug("stop: executing")
    await podAVPlayer.stop()
    nowPlayingInfo = nil
    await playState.setOnDeck(nil)
    await setStatus(.stopped)
  }

  private func setStatus(_ status: PlayState.Status) async {
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

  private func handleCurrentItemChange(_ podcastEpisode: PodcastEpisode?) async {
    if let podcastEpisode {
      log.debug("handleCurrentItemChange: \(podcastEpisode.id)")

      do {
        try await queue.dequeue(podcastEpisode.id)
      } catch {
        Log.error(error, from: log)
      }

      await setOnDeck(podcastEpisode)
    } else {
      log.debug("handleCurrentItemChange: nil, stopping")

      await stop()

      do {
        if let nextEpisode = try await queue.nextEpisode {
          try await load(nextEpisode)
          await play()
        }
      } catch {
        Log.error(error, from: log)
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
          Log.error(error, from: log)
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
        await handleCurrentItemChange(podcastEpisode)
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
        case AVPlayer.TimeControlStatus.paused:
          await setStatus(.paused)
        case AVPlayer.TimeControlStatus.playing:
          await setStatus(.playing)
        case AVPlayer.TimeControlStatus.waitingToPlayAtSpecifiedRate:
          await setStatus(.waiting)
        @unknown default:
          Assert.fatal("Time control status unknown?")
        }
      }
    }
  }
}
