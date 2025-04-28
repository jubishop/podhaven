// Copyright Justin Bishop, 2025

import AVFoundation
import Factory
import Foundation
import GRDB
import Tagged

struct PlayManagerAccessKey { fileprivate init() {} }

extension Container {
  var playManager: Factory<PlayManager> {
    Factory(self) { PlayManager() }.scope(.singleton)
  }
}

final actor PlayManager {
  // MARK: - State Management

  // Cannot LazyInject because @MainActor
  private var playState = Container.shared.playState()

  @ObservationIgnored @LazyInjected(\.images) private var images
  @ObservationIgnored @LazyInjected(\.observatory) private var observatory
  @ObservationIgnored @LazyInjected(\.queue) private var queue
  @ObservationIgnored @LazyInjected(\.repo) private var repo

  private let accessKey = PlayManagerAccessKey()
  private var _status: PlayState.Status = .stopped
  private var status: PlayState.Status { _status }

  private var currentPodcastEpisode: PodcastEpisode? {
    didSet {
      Persistence.currentEpisodeID.save(currentPodcastEpisode?.id)
    }
  }

  private struct LoadedPodcastEpisode {
    let asset: AVURLAsset
    let podcastEpisode: PodcastEpisode
    let duration: CMTime
  }
  private var loadedNextPodcastEpisode: LoadedPodcastEpisode?

  private var avPlayer = AVQueuePlayer()
  private var nowPlayingInfo: NowPlayingInfo? {
    willSet {
      if newValue == nil {
        nowPlayingInfo?.clear()
      }
    }
    didSet {
      nowPlayingInfo == nil ? commandCenter.stop() : commandCenter.start()
    }
  }

  private var commandCenter: CommandCenter
  var timeControlStatusObserver: NSKeyValueObservation?
  private var periodicTimeObserver: Any?

  // MARK: - Convenience Getters

  private var audioSession: AVAudioSession { AVAudioSession.sharedInstance() }
  private var notificationCenter: NotificationCenter { NotificationCenter.default }

  // MARK: - Initialization

  fileprivate init() {
    commandCenter = CommandCenter(accessKey)
  }

  func begin() async {
    startTracking()

    guard let currentEpisodeID: Episode.ID = Persistence.currentEpisodeID.load(),
      let podcastEpisode = try? await repo.episode(currentEpisodeID)
    else { return }

    try? await load(podcastEpisode)
  }

  // MARK: - Loading

  func load(_ podcastEpisode: PodcastEpisode) async throws {
    guard podcastEpisode != currentPodcastEpisode else { return }

    if status == .loading { return }
    await setStatus(.loading)
    defer {
      if status != .active {
        Task { await setStatus(.stopped) }
      }
    }

    if let currentPodcastEpisode = self.currentPodcastEpisode {
      try? await queue.unshift(currentPodcastEpisode.id)
    }
    await clearOnDeck()

    try audioSession.setActive(true)
    let (avAsset, duration) = try await loadAsset(for: podcastEpisode)

    avPlayer.removeAllItems()
    avPlayer.insert(AVPlayerItem(asset: avAsset), after: nil)

    await setOnDeck(podcastEpisode, duration)
    try? await queue.dequeue(podcastEpisode.id)
    updateNextPodcastEpisodeInAVPlayer()

    await setStatus(.active)
  }

  private func loadAsset(for podcastEpisode: PodcastEpisode) async throws -> (AVURLAsset, CMTime) {
    let avAsset = AVURLAsset(url: podcastEpisode.episode.media.rawValue)
    let (isPlayable, duration) = try await avAsset.load(.isPlayable, .duration)

    guard isPlayable
    else {
      throw Err.andPrint(
        .msg(
          """
          [Playback Error]
            PodcastEpisode: \(podcastEpisode.toString)
            MediaURL: \(podcastEpisode.episode.media)
            Reason: URL is not playable.
          """
        )
      )
    }

    return (avAsset, duration)
  }

  // MARK: - Playback Controls

  func play() {
    guard status.playable
    else { return }

    avPlayer.play()
  }

  func pause() {
    avPlayer.pause()
  }

  // MARK: - Seeking

  func seekForward(_ duration: CMTime) async {
    await seek(to: avPlayer.currentTime() + duration)
  }

  func seekBackward(_ duration: CMTime) async {
    await seek(to: avPlayer.currentTime() - duration)
  }

  func seek(to time: CMTime) async {
    removePeriodicTimeObserver()
    await setCurrentTime(time)
    avPlayer.seek(to: time) { [unowned self] completed in
      if completed {
        Task { await addPeriodicTimeObserver() }
      }
    }
  }

  // MARK: - Private State Management

  private func setOnDeck(_ podcastEpisode: PodcastEpisode, _ duration: CMTime) async {
    guard podcastEpisode != currentPodcastEpisode else { return }
    currentPodcastEpisode = podcastEpisode

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

    addPeriodicTimeObserver()
    if podcastEpisode.episode.currentTime != CMTime.zero {
      await seek(to: podcastEpisode.episode.currentTime)
    } else {
      await setCurrentTime(CMTime.zero)
    }
  }

  private func clearOnDeck() async {
    nowPlayingInfo = nil
    await playState.setOnDeck(nil, accessKey)

    removePeriodicTimeObserver()
    await setCurrentTime(CMTime.zero)

    currentPodcastEpisode = nil
  }

  private func updateNextPodcastEpisodeInAVPlayer() {
    guard !avPlayer.items().isEmpty
    else { return }

    while avPlayer.items().count > 1, let lastItem = avPlayer.items().last {
      avPlayer.remove(lastItem)
    }

    if let loadedNextPodcastEpisode = self.loadedNextPodcastEpisode {
      avPlayer.insert(
        AVPlayerItem(asset: loadedNextPodcastEpisode.asset),
        after: avPlayer.items().first
      )
    }
  }

  private func setStatus(_ status: PlayState.Status) async {
    guard status != _status else { return }

    print("setting status: \(status)")
    nowPlayingInfo?.playing(status.playing)
    await playState.setStatus(status, accessKey)
    _status = status
  }

  private func setCurrentTime(_ currentTime: CMTime) async {
    nowPlayingInfo?.currentTime(currentTime)
    await playState.setCurrentTime(currentTime, accessKey)
    Task(priority: .utility) {
      guard let currentPodcastEpisode = self.currentPodcastEpisode else { return }

      try await repo.updateCurrentTime(currentPodcastEpisode.id, currentTime)
    }
  }

  // MARK: - Private Change Handlers

  private func handleCurrentEpisodeFinished() async {
    if let currentPodcastEpisode = self.currentPodcastEpisode {
      self.currentPodcastEpisode = nil
      _ = try? await repo.markComplete(currentPodcastEpisode.id)
    }

    if let loadedNextPodcastEpisode = self.loadedNextPodcastEpisode {
      self.loadedNextPodcastEpisode = nil
      let podcastEpisode = loadedNextPodcastEpisode.podcastEpisode
      let duration = loadedNextPodcastEpisode.duration
      await setOnDeck(podcastEpisode, duration)
      try? await queue.dequeue(podcastEpisode.id)
    } else {
      await clearOnDeck()
      await setStatus(.stopped)
    }
  }

  private func handleNextEpisodeChange(_ nextPodcastEpisode: PodcastEpisode?) async {
    if let podcastEpisode = nextPodcastEpisode {
      do {
        let (avAsset, duration) = try await loadAsset(for: podcastEpisode)
        self.loadedNextPodcastEpisode = LoadedPodcastEpisode(
          asset: avAsset,
          podcastEpisode: podcastEpisode,
          duration: duration
        )
      } catch {
        self.loadedNextPodcastEpisode = nil
      }
    } else {
      self.loadedNextPodcastEpisode = nil
    }
    updateNextPodcastEpisodeInAVPlayer()
  }

  // MARK: - Private Tracking

  private func startTracking() {
    addTimeControlStatusObserver()
    addPeriodicTimeObserver()
    observeNextEpisode()
    startListeningToCommandCenter()
    startInterruptionNotifications()
    startPlayToEndTimeNotifications()
  }

  private func addPeriodicTimeObserver() {
    guard self.periodicTimeObserver == nil
    else { return }

    self.periodicTimeObserver = avPlayer.addPeriodicTimeObserver(
      forInterval: CMTime.inSeconds(1),
      queue: .global(qos: .utility)
    ) { currentTime in
      Task { [unowned self] in
        await setCurrentTime(currentTime)
      }
    }
  }

  private func removePeriodicTimeObserver() {
    if let periodicTimeObserver = self.periodicTimeObserver {
      avPlayer.removeTimeObserver(periodicTimeObserver)
      self.periodicTimeObserver = nil
    }
  }

  private func addTimeControlStatusObserver() {
    self.timeControlStatusObserver = avPlayer.observe(
      \.timeControlStatus,
      options: [.initial, .new],
      changeHandler: { [unowned self] playerItem, _ in
        Task {
          if !(await status.playable) { return }
          switch playerItem.timeControlStatus {
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
    )
  }

  private func observeNextEpisode() {
    Task {
      for try await nextPodcastEpisode in observatory.nextPodcastEpisode()
      where nextPodcastEpisode?.id != self.loadedNextPodcastEpisode?.podcastEpisode.id {
        await handleNextEpisodeChange(nextPodcastEpisode)
      }
    }
  }

  private func startListeningToCommandCenter() {
    Task {
      for await command in commandCenter.commandStream() {
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

  private func startInterruptionNotifications() {
    Task {
      for await notification in notificationCenter.notifications(
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

  private func startPlayToEndTimeNotifications() {
    Task {
      for await _ in notificationCenter.notifications(
        named: AVPlayerItem.didPlayToEndTimeNotification
      ) {
        await handleCurrentEpisodeFinished()
      }
    }
  }
}
