// Copyright Justin Bishop, 2025

import AVFoundation
import FactoryKit
import Foundation
import GRDB
import Logging
import Semaphore
import Sharing

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

  private var status: PlayState.Status = .stopped
  private var nowPlayingInfo: NowPlayingInfo? {
    willSet {
      if newValue == nil {
        log.debug("nowPlayingInfo: nil")
        nowPlayingInfo?.clear()
      }
    }
  }

  private var loadingTask: Task<Void, any Error>?

  // MARK: - Initialization

  fileprivate init() {}

  func start() async {
    startInterruptionNotifications()
    startListeningToCommandCenter()
    startListeningToCurrentItem()
    startListeningToCurrentTime()
    startListeningToControlStatus()

    guard let currentEpisodeID = currentEpisodeID,
      let podcastEpisode = try? await repo.episode(currentEpisodeID)
    else { return }

    try? await load(podcastEpisode)
  }

  // MARK: - Loading

  func load(_ podcastEpisode: PodcastEpisode) async throws(PlaybackError) {
    loadingTask?.cancel()

    return try await PlaybackError.catch {
      try await performLoad(podcastEpisode)
    }
  }

  private func performLoad(_ podcastEpisode: PodcastEpisode) async throws {
    let task = Task {
      let outgoingPodcastEpisode = await podAVPlayer.podcastEpisode
      do {
        await setStatus(.loading)

        log.info("performLoad: \(podcastEpisode.toString)")
        await pause()
        await setOnDeck(try await podAVPlayer.load(podcastEpisode))

        log.debug("performLoad: dequeueing incoming episode: \(podcastEpisode.toString)")
        try? await queue.dequeue(podcastEpisode.id)

        if let outgoingPodcastEpisode {
          log.debug("performLoad: unshifting current episode: \(outgoingPodcastEpisode.toString)")
          try? await queue.unshift(outgoingPodcastEpisode.id)
        } else if let nextPodcastEpisode = try? await queue.nextEpisode {
          log.debug("performLoad: setting next episode: \(nextPodcastEpisode.toString)")
          try? await podAVPlayer.setNextPodcastEpisode(nextPodcastEpisode)
        }

        await setStatus(.active)
      } catch {
        log.notice(ErrorKit.loggableMessage(for: error))

        if let outgoingPodcastEpisode {
          try? await queue.unshift(outgoingPodcastEpisode.id)
        }

        await stopAndClearOnDeck()

        throw error
      }
    }

    loadingTask = task
    defer { loadingTask = nil }

    try await task.value
  }

  // MARK: - Playback Controls

  func play() async {
    Assert.precondition(
      status.playable,
      "tried to play but status is \(status) which is not playable"
    )

    await podAVPlayer.play()
  }

  func pause() async {
    await podAVPlayer.pause()
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

  private func setOnDeck(_ loadedPodcastEpisode: LoadedPodcastEpisode) async {
    log.debug("setOnDeck: \(loadedPodcastEpisode.toString)")

    let podcastEpisode = loadedPodcastEpisode.podcastEpisode

    let imageURL = podcastEpisode.episode.image ?? podcastEpisode.podcast.image
    let onDeck = OnDeck(
      feedURL: podcastEpisode.podcast.feedURL,
      guid: podcastEpisode.episode.guid,
      podcastTitle: podcastEpisode.podcast.title,
      podcastURL: podcastEpisode.podcast.link,
      episodeTitle: podcastEpisode.episode.title,
      duration: loadedPodcastEpisode.duration,
      image: try? await images.fetchImage(imageURL),
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
    }

    currentEpisodeID = podcastEpisode.id
  }

  private func stopAndClearOnDeck() async {
    log.debug("stopAndClearOnDeck: executing")
    await podAVPlayer.stop()
    nowPlayingInfo = nil
    await playState.setOnDeck(nil)
    await setStatus(.stopped)
  }

  private func setStatus(_ status: PlayState.Status) async {
    guard status != self.status
    else { return }

    log.debug("setStatus: \(status)")
    nowPlayingInfo?.playing(status.playing)
    await playState.setStatus(status)
    self.status = status
  }

  private func setCurrentTime(_ currentTime: CMTime) async {
    guard let currentPodcastEpisode = await podAVPlayer.podcastEpisode
    else { return }

    log.trace("setCurrentTime: \(currentTime)")

    nowPlayingInfo?.setCurrentTime(currentTime)
    await playState.setCurrentTime(currentTime)

    _ = try? await repo.updateCurrentTime(currentPodcastEpisode.id, currentTime)
  }

  // MARK: - Private Change Handlers

  private func handleCurrentItemChanged() async {
  }

  // MARK: - Private Tracking

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
          if status.playing { await pause() } else { await play() }
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
      for await _ in await podAVPlayer.currentItemStream {
        await handleCurrentItemChanged()
      }
    }
  }

  private func startListeningToCurrentTime() {
    Assert.neverCalled()

    Task {
      for await currentTime in await podAVPlayer.currentTimeStream {
        await setCurrentTime(currentTime)
      }
    }
  }

  private func startListeningToControlStatus() {
    Assert.neverCalled()

    Task {
      for await controlStatus in await podAVPlayer.controlStatusStream {
        if !status.playable { continue }
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
