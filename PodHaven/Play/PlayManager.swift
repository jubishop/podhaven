// Copyright Justin Bishop, 2025

import AVFoundation
import Factory
import Foundation
import GRDB

struct PlayManagerAccessKey { fileprivate init() {} }

extension Container {
  var playManager: Factory<PlayManager> {
    Factory(self) { @PlayActor in PlayManager() }.scope(.singleton)
  }
}

@PlayActor final class PlayManager {
  // Cannot LazyInject because @MainActor
  private var playState = Container.shared.playState()

  @ObservationIgnored @LazyInjected(\.images) private var images
  @ObservationIgnored @LazyInjected(\.observatory) private var observatory
  @ObservationIgnored @LazyInjected(\.queue) private var queue
  @ObservationIgnored @LazyInjected(\.repo) private var repo

  // MARK: - State Management

  private let accessKey = PlayManagerAccessKey()
  private var _status: PlayState.Status = .stopped
  private var status: PlayState.Status { _status }

  private var nowPlayingInfo: NowPlayingInfo? {
    willSet {
      if newValue == nil {
        nowPlayingInfo?.clear()
      }
    }
  }
  private var commandCenter: CommandCenter
  private var podAVPlayer: PodAVPlayer

  // MARK: - Initialization

  fileprivate init() {
    commandCenter = CommandCenter(accessKey)
    podAVPlayer = PodAVPlayer(accessKey)
    startTracking()
  }

  func start() async {
    guard let currentEpisodeID: Episode.ID = Persistence.currentEpisodeID.load(),
      let podcastEpisode = try? await repo.episode(currentEpisodeID)
    else { return }

    try? await load(podcastEpisode)
  }

  // MARK: - Loading

  func load(_ podcastEpisode: PodcastEpisode) async throws {
    guard podcastEpisode != podAVPlayer.podcastEpisode else { return }

    if status == .loading { return }
    await setStatus(.loading)
    defer {
      if status != .active {
        Task { await setStatus(.stopped) }
      }
    }

    if let outgoingPodcastEpisode = podAVPlayer.podcastEpisode {
      try? await queue.unshift(outgoingPodcastEpisode.id)
    }
    await stopAndClearOnDeck()
    let duration = try await podAVPlayer.load(podcastEpisode)
    await setOnDeck(podcastEpisode, duration)
    try? await queue.dequeue(podcastEpisode.id)

    await setStatus(.active)
  }

  // MARK: - Playback Controls

  func play() {
    guard status.playable
    else { return }

    podAVPlayer.play()
  }

  func pause() {
    podAVPlayer.pause()
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
      pubDate: podcastEpisode.episode.pubDate,
      key: accessKey
    )

    nowPlayingInfo = NowPlayingInfo(onDeck, accessKey)
    await playState.setOnDeck(onDeck, accessKey)

    if podcastEpisode.episode.currentTime != CMTime.zero {
      await seek(to: podcastEpisode.episode.currentTime)
    } else {
      await setCurrentTime(CMTime.zero)
    }
  }

  private func stopAndClearOnDeck() async {
    podAVPlayer.stop()
    nowPlayingInfo = nil
    await playState.setOnDeck(nil, accessKey)
    await setCurrentTime(CMTime.zero)
  }

  private func setStatus(_ status: PlayState.Status) async {
    guard status != _status else { return }

    nowPlayingInfo?.playing(status.playing)
    await playState.setStatus(status, accessKey)
    _status = status
  }

  private func setCurrentTime(_ currentTime: CMTime) async {
    nowPlayingInfo?.currentTime(currentTime)
    await playState.setCurrentTime(currentTime, accessKey)
    Task(priority: .utility) {
      guard let currentPodcastEpisode = podAVPlayer.podcastEpisode
      else { return }

      try await repo.updateCurrentTime(currentPodcastEpisode.id, currentTime)
    }
  }

  // MARK: - Private Change Handlers

  private func handleEpisodeFinished(
    finishedPodcastEpisode: PodcastEpisode,
    currentLoadedPodcastEpisode: LoadedPodcastEpisode?
  ) async {
    _ = try? await repo.markComplete(finishedPodcastEpisode.id)

    if let currentLoadedPodcastEpisode = currentLoadedPodcastEpisode {
      let podcastEpisode = currentLoadedPodcastEpisode.podcastEpisode
      let duration = currentLoadedPodcastEpisode.duration
      await setOnDeck(podcastEpisode, duration)
      try? await queue.dequeue(podcastEpisode.id)
    } else {
      await stopAndClearOnDeck()
      await setStatus(.stopped)
    }
  }

  // MARK: - Private Tracking

  private func startTracking() {
    observeNextEpisode()
    startInterruptionNotifications()
    startListeningToCommandCenter()
    startListeningToPodAVPlayer()
  }

  private func observeNextEpisode() {
    Task {
      for try await nextPodcastEpisode in observatory.nextPodcastEpisode() {
        await podAVPlayer.setNextPodcastEpisode(nextPodcastEpisode)
      }
    }
  }

  private func startListeningToCommandCenter() {
    Task {
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

  private func startListeningToPodAVPlayer() {
    Task {
      for await currentTime in podAVPlayer.currentTimeStream {
        await self.setCurrentTime(currentTime)
      }
    }

    Task {
      for await controlStatus in podAVPlayer.controlStatusStream {
        if !status.playable { continue }
        switch controlStatus {
        case AVPlayer.TimeControlStatus.paused:
          await self.setStatus(.paused)
        case AVPlayer.TimeControlStatus.playing:
          await self.setStatus(.playing)
        case AVPlayer.TimeControlStatus.waitingToPlayAtSpecifiedRate:
          await self.setStatus(.waiting)
        @unknown default:
          fatalError("Time control status unknown?")
        }
      }
    }

    Task {
      for await (finishedPodcastEpisode, currentLoadedPodcastEpisode) in podAVPlayer.playToEndStream
      {
        await handleEpisodeFinished(
          finishedPodcastEpisode: finishedPodcastEpisode,
          currentLoadedPodcastEpisode: currentLoadedPodcastEpisode
        )
      }
    }
  }

  private func startInterruptionNotifications() {
    Task {
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
}
