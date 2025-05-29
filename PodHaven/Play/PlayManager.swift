// Copyright Justin Bishop, 2025

import AVFoundation
import FactoryKit
import Foundation
import GRDB
import Logging
import Semaphore
import Sharing

extension Container {
  @PlayActor
  var playManager: Factory<PlayManager> {
    Factory(self) { @PlayActor in PlayManager() }.scope(.cached)
  }
}

@PlayActor final class PlayManager {
  @DynamicInjected(\.commandCenter) private var commandCenter
  @DynamicInjected(\.images) private var images
  @DynamicInjected(\.observatory) private var observatory
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
        log.debug("Clearing nowPlayingInfo")
        nowPlayingInfo?.clear()
      }
    }
  }

  private var loadingTask: Task<Void, any Error>?
  private var nextEpisodeTask: Task<Void, any Error>?
  private let nextEpisodeSemaphore = AsyncSemaphore(value: 1)
  private var interruptionTask: Task<Void, Never>?
  private var commandCenterTask: Task<Void, Never>?
  private var currentTimeTask: Task<Void, Never>?
  private var controlStatusTask: Task<Void, Never>?
  private var playToEndTask: Task<Void, Never>?

  // MARK: - Initialization

  fileprivate init() {
    observeNextEpisode()
    startInterruptionNotifications()
    startListeningToCommandCenter()
    startListeningToCurrentTime()
    startListeningToControlStatus()
    startListeningToPlayToEnd()
  }

  func start() async {
    guard let currentEpisodeID = currentEpisodeID,
      let podcastEpisode = try? await repo.episode(currentEpisodeID)
    else { return }

    try? await load(podcastEpisode)
  }

  // MARK: - Loading

  func load(_ podcastEpisode: PodcastEpisode) async throws(PlaybackError) {
    guard await podAVPlayer.podcastEpisode != podcastEpisode
    else { Assert.fatal("Loading podcast \(podcastEpisode.toString) that's already loaded") }

    if status == .loading {
      guard let loadingTask = loadingTask
      else { Assert.fatal("loadingTask should not be nil if status is loading still") }

      loadingTask.cancel()
    }

    defer {
      self.loadingTask = nil
      if status != .active {
        log.notice("load.defer: Status in load never became active, going back to stopped")
        Task { await setStatus(.stopped) }
      }
    }

    let task = Task {
      await setStatus(.loading)

      log.info("playManager loading: \(podcastEpisode.toString)")

      if let outgoingPodcastEpisode = await podAVPlayer.podcastEpisode {
        log.debug("load: unshifting current episode: \(outgoingPodcastEpisode.toString)")
        try? await queue.unshift(outgoingPodcastEpisode.id)
      }

      await stopAndClearOnDeck()

      let duration = try await podAVPlayer.load(podcastEpisode)
      await setOnDeck(podcastEpisode, duration)
      try? await queue.dequeue(podcastEpisode.id)

      await setStatus(.active)
    }

    self.loadingTask = task
    try await PlaybackError.catch {
      try await task.value
    }
  }

  // MARK: - Playback Controls

  func play() {
    Assert.precondition(
      status.playable,
      "tried to play but status is \(status) which is not playable"
    )

    Task { await podAVPlayer.play() }
  }

  func pause() {
    Task { await podAVPlayer.pause() }
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

  private func setOnDeck(_ podcastEpisode: PodcastEpisode, _ duration: CMTime) async {
    log.debug("Setting on deck: \(podcastEpisode.toString), with duration: \(duration)")

    let imageURL = podcastEpisode.episode.image ?? podcastEpisode.podcast.image
    let onDeck = OnDeck(
      feedURL: podcastEpisode.podcast.feedURL,
      guid: podcastEpisode.episode.guid,
      podcastTitle: podcastEpisode.podcast.title,
      podcastURL: podcastEpisode.podcast.link,
      episodeTitle: podcastEpisode.episode.title,
      duration: duration,
      image: try? await images.fetchImage(imageURL),
      media: podcastEpisode.episode.media,
      pubDate: podcastEpisode.episode.pubDate
    )

    nowPlayingInfo = Container.shared.nowPlayingInfo(onDeck)
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
      log.debug("setOnDeck: \(podcastEpisode.toString) has no currentTime")
    }

    currentEpisodeID = podcastEpisode.id
  }

  private func stopAndClearOnDeck() async {
    log.debug("stopAndClearOnDeck: executing")
    await podAVPlayer.stop()
    nowPlayingInfo = nil
    await playState.setOnDeck(nil)
    await setCurrentTime(CMTime.zero)
  }

  private func setStatus(_ status: PlayState.Status) async {
    guard status != self.status
    else {
      log.debug("setStatus: status is already \(status) so nothing to do")
      return
    }

    nowPlayingInfo?.playing(status.playing)
    await playState.setStatus(status)
    self.status = status
  }

  private func setCurrentTime(_ currentTime: CMTime) async {
    nowPlayingInfo?.currentTime(currentTime)
    await playState.setCurrentTime(currentTime)

    guard let currentPodcastEpisode = await podAVPlayer.podcastEpisode
    else {
      Assert.precondition(
        currentTime == .zero,
        "tried to set current time to: \(currentTime) but there is no current episode?"
      )
      return
    }

    _ = try? await repo.updateCurrentTime(currentPodcastEpisode.id, currentTime)
  }

  // MARK: - Private Change Handlers

  private func handleEpisodeFinished(
    finishedPodcastEpisode: PodcastEpisode,
    currentEpisodeInfo: EpisodeInfo?
  ) async {
    _ = try? await repo.markComplete(finishedPodcastEpisode.id)

    if let currentEpisodeInfo = currentEpisodeInfo {
      log.debug(
        """
        handleEpisodeFinished: enqueuing next episode: \
        \(currentEpisodeInfo.toString)
        """
      )
      let podcastEpisode = currentEpisodeInfo.podcastEpisode
      let duration = currentEpisodeInfo.duration
      await setOnDeck(podcastEpisode, duration)
      try? await queue.dequeue(podcastEpisode.id)
    } else {
      log.debug("handleEpisodeFinished: no more episodes to play")
      await stopAndClearOnDeck()
      await setStatus(.stopped)
    }
  }

  // MARK: - Private Tracking

  private func observeNextEpisode() {
    Assert.precondition(
      self.nextEpisodeTask == nil,
      "nextEpisodeTask already exists?"
    )

    self.nextEpisodeTask = Task {
      do {
        for try await nextPodcastEpisode in observatory.nextPodcastEpisode() {
          await nextEpisodeSemaphore.wait()
          await podAVPlayer.setNextPodcastEpisode(nextPodcastEpisode)
          nextEpisodeSemaphore.signal()
        }
      } catch {
        log.error(ErrorKit.loggableMessage(for: error))
      }
    }
  }

  private func startInterruptionNotifications() {
    Assert.precondition(
      self.interruptionTask == nil,
      "interruptionTask already exists?"
    )

    self.interruptionTask = Task {
      for await notification in NotificationCenter.default.notifications(
        named: AVAudioSession.interruptionNotification
      ) {
        switch AudioInterruption.parse(notification) {
        case .pause:
          pause()
        case .resume:
          play()
        case .ignore:
          break
        }
      }
    }
  }

  private func startListeningToCommandCenter() {
    Assert.precondition(
      self.commandCenterTask == nil,
      "commandCenterTask already exists?"
    )

    self.commandCenterTask = Task {
      for await command in commandCenter.stream {
        switch command {
        case .play:
          play()
        case .pause:
          pause()
        case .togglePlayPause:
          if status.playing { pause() } else { play() }
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

  private func startListeningToCurrentTime() {
    Assert.precondition(
      self.currentTimeTask == nil,
      "currentTimeTask already exists?"
    )

    self.currentTimeTask = Task {
      for await currentTime in await podAVPlayer.currentTimeStream {
        await self.setCurrentTime(currentTime)
      }
    }
  }

  private func startListeningToControlStatus() {
    Assert.precondition(
      self.controlStatusTask == nil,
      "controlStatusTask already exists?"
    )

    self.controlStatusTask = Task {
      for await controlStatus in await podAVPlayer.controlStatusStream {
        if !status.playable { continue }
        switch controlStatus {
        case AVPlayer.TimeControlStatus.paused:
          await self.setStatus(.paused)
        case AVPlayer.TimeControlStatus.playing:
          await self.setStatus(.playing)
        case AVPlayer.TimeControlStatus.waitingToPlayAtSpecifiedRate:
          await self.setStatus(.waiting)
        @unknown default:
          Assert.fatal("Time control status unknown?")
        }
      }
    }
  }

  private func startListeningToPlayToEnd() {
    Assert.precondition(
      self.playToEndTask == nil,
      "playToEndTask already exists?"
    )

    self.playToEndTask = Task {
      for await (finishedPodcastEpisode, currentEpisodeInfo)
        in await podAVPlayer.playToEndStream
      {
        await handleEpisodeFinished(
          finishedPodcastEpisode: finishedPodcastEpisode,
          currentEpisodeInfo: currentEpisodeInfo
        )
      }
    }
  }
}
