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

  private var loadTask: Task<Void, any Error>?

  // MARK: - Initialization

  fileprivate init() {}

  func start() async {
    startInterruptionNotifications()
    startListeningToCommandCenter()
    startListeningToCurrentItem()
    startListeningToDidPlayToEnd()
    startListeningToCurrentTime()
    startListeningToControlStatus()

    if let currentEpisodeID {
      do {
        if let podcastEpisode = try await repo.episode(currentEpisodeID) {
          try await load(podcastEpisode)
        }
      } catch {
        if ErrorKit.isRemarkable(error) {
          log.error(ErrorKit.loggableMessage(for: error))
        }
      }
    }
  }

  // MARK: - Loading

  func load(_ podcastEpisode: PodcastEpisode) async throws(PlaybackError) {
    loadTask?.cancel()

    return try await PlaybackError.catch {
      try await performLoad(podcastEpisode)
    }
  }

  private func performLoad(_ podcastEpisode: PodcastEpisode) async throws {
    let outgoingPodcastEpisode = await podAVPlayer.podcastEpisode

    if outgoingPodcastEpisode == podcastEpisode { return }

    let task = Task {
      do {
        await podAVPlayer.removeTransientObservers()
        await setStatus(.loading)

        log.info("performLoad: \(podcastEpisode.toString)")

        await pause()
        await setOnDeck(try await podAVPlayer.load(podcastEpisode))

        log.debug("performLoad: dequeueing incoming episode: \(podcastEpisode.toString)")
        do {
          try await queue.dequeue(podcastEpisode.id)
        } catch {
          if ErrorKit.isRemarkable(error) {
            log.error(ErrorKit.loggableMessage(for: error))
          }
        }

        if let outgoingPodcastEpisode {
          log.debug("performLoad: unshifting current episode: \(outgoingPodcastEpisode.toString)")
          do {
            try await queue.unshift(outgoingPodcastEpisode.id)
          } catch {
            if ErrorKit.isRemarkable(error) {
              log.error(ErrorKit.loggableMessage(for: error))
            }
          }
        }

        do {
          if let nextPodcastEpisode = try await queue.nextEpisode {
            log.debug("performLoad: setting next episode: \(nextPodcastEpisode.toString)")
            try await podAVPlayer.setNextPodcastEpisode(nextPodcastEpisode)
          }
        } catch {
          if ErrorKit.isRemarkable(error) {
            log.error(ErrorKit.loggableMessage(for: error))
          }
        }

        await podAVPlayer.addTransientObservers()
      } catch {
        if let outgoingPodcastEpisode {
          do {
            try await queue.unshift(outgoingPodcastEpisode.id)
          } catch {
            if ErrorKit.isRemarkable(error) {
              log.error(ErrorKit.loggableMessage(for: error))
            }
          }
        }

        do {
          try await queue.unshift(podcastEpisode.id)
        } catch {
          if ErrorKit.isRemarkable(error) {
            log.error(ErrorKit.loggableMessage(for: error))
          }
        }

        await stop()

        throw error
      }
    }

    loadTask = task
    defer { loadTask = nil }

    try await task.value
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
          if ErrorKit.isRemarkable(error) {
            log.error(ErrorKit.loggableMessage(for: error))
          }
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
      do {
        try await queue.dequeue(podcastEpisode.id)
      } catch {
        if ErrorKit.isRemarkable(error) {
          log.error(ErrorKit.loggableMessage(for: error))
        }
      }

      await setOnDeck(podcastEpisode)
    } else {
      await stop()

      do {
        if let nextEpisode = try await queue.nextEpisode {
          try await load(nextEpisode)
          await play()
        }
      } catch {
        if ErrorKit.isRemarkable(error) {
          log.error(ErrorKit.loggableMessage(for: error))
        }
      }
    }
  }

  private func handleDidPlayToEnd(_ podcastEpisode: PodcastEpisode) async throws {
    try await repo.markComplete(podcastEpisode.id)
  }

  // MARK: - Private State Tracking

  private func startInterruptionNotifications() {
    Assert.neverCalled()

    Task {
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
  }

  private func startListeningToCommandCenter() {
    Assert.neverCalled()

    Task {
      for await command in commandCenter.stream {
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

    Task {
      for await podcastEpisode in await podAVPlayer.currentItemStream {
        await handleCurrentItemChange(podcastEpisode)
      }
    }
  }

  private func startListeningToDidPlayToEnd() {
    Assert.neverCalled()

    Task {
      for await podcastEpisode in await podAVPlayer.didPlayToEndStream {
        do {
          try await handleDidPlayToEnd(podcastEpisode)
        } catch {
          if ErrorKit.isRemarkable(error) {
            log.error(ErrorKit.loggableMessage(for: error))
          }
        }
      }
    }
  }

  private func startListeningToCurrentTime() {
    Assert.neverCalled()

    Task {
      for await currentTime in await podAVPlayer.currentTimeStream {
        do {
          await setCurrentTime(currentTime)

          guard let currentPodcastEpisode = await podAVPlayer.podcastEpisode
          else { throw PlaybackError.settingCurrentTimeOnNil(currentTime) }

          try await repo.updateCurrentTime(currentPodcastEpisode.id, currentTime)
        } catch {
          if ErrorKit.isRemarkable(error) {
            log.error(ErrorKit.loggableMessage(for: error))
          }
        }
      }
    }
  }

  private func startListeningToControlStatus() {
    Assert.neverCalled()

    Task {
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
