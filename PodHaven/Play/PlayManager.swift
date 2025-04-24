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

  private var playState = Container.shared.playState()  // Cannot LazyInject because @MainActor
  @ObservationIgnored @LazyInjected(\.images) private var images
  @ObservationIgnored @LazyInjected(\.observatory) private var observatory
  @ObservationIgnored @LazyInjected(\.queue) private var queue
  @ObservationIgnored @LazyInjected(\.repo) private var repo

  private let accessKey = PlayManagerAccessKey()
  private var _status: PlayState.Status = .stopped
  private var status: PlayState.Status { _status }

  private var currentEpisodeID: Episode.ID?

  private struct PodcastEpisodeWithDuration {
    let podcastEpisode: PodcastEpisode
    let duration: CMTime
  }
  private var nextPodcastEpisode: PodcastEpisodeWithDuration?

  private var avPlayer = AVQueuePlayer()
  private var nowPlayingInfo: NowPlayingInfo?
  private var commandCenter: CommandCenter
  private var commandObservingTask: Task<Void, Never>?
  private var interruptionObservingTask: Task<Void, Never>?
  private var playToEndObservingTask: Task<Void, Never>?
  private var keyValueObservers = [NSKeyValueObservation](capacity: 1)
  private var timeObserver: Any?

  // MARK: - Convenience Getters

  private var audioSession: AVAudioSession { AVAudioSession.sharedInstance() }
  private var notificationCenter: NotificationCenter { NotificationCenter.default }

  // MARK: - Initialization

  fileprivate init() {
    commandCenter = CommandCenter(accessKey)
    Task { try await observeNextEpisode() }
  }

  func resume() async {
    guard let currentEpisodeID: Episode.ID = Persistence.currentEpisodeID.load(),
      let podcastEpisode = try? await repo.episode(currentEpisodeID)
    else { return }

    try? await load(podcastEpisode)
  }

  // MARK: - Loading

  func load(_ podcastEpisode: PodcastEpisode) async throws {
    guard podcastEpisode.id != currentEpisodeID else { return }

    if status == .loading { return }
    setStatus(.loading)
    defer {
      if status != .active { setStatus(.stopped) }
    }

    stopTracking()
    pause()

    try audioSession.setActive(true)
    let (avAsset, duration) = try await loadAsset(for: podcastEpisode.episode.media)

    let avPlayerItem = AVPlayerItem(asset: avAsset)
    avPlayer.removeAllItems()
    avPlayer.insert(avPlayerItem, after: nil)

    await setOnDeck(podcastEpisode, duration)

    setStatus(.active)
    startTracking()
  }

  // MARK: - Playback Controls

  func play() {
    guard status.playable else { return }

    avPlayer.play()
  }

  func pause() {
    avPlayer.pause()
  }

  // MARK: - Seeking

  func seekForward(_ duration: CMTime) {
    seek(to: avPlayer.currentTime() + duration)
  }

  func seekBackward(_ duration: CMTime) {
    seek(to: avPlayer.currentTime() - duration)
  }

  func seek(to time: CMTime) {
    removeTimeObserver()
    setCurrentTime(time)
    avPlayer.seek(to: time) { [unowned self] completed in
      if completed {
        Task { await addTimeObserver() }
      }
    }
  }

  // MARK: - Private State Management

  private func setOnDeck(_ podcastEpisode: PodcastEpisode, _ duration: CMTime) async {
    guard podcastEpisode.id != currentEpisodeID else { return }

    if let currentEpisodeID = self.currentEpisodeID {
      try? await queue.unshift(currentEpisodeID)
    }
    self.currentEpisodeID = nil
    try? await queue.dequeue(podcastEpisode.id)
    self.currentEpisodeID = podcastEpisode.id

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
    Task { await playState.setOnDeck(onDeck, accessKey) }
    Task(priority: .utility) { Persistence.currentEpisodeID.save(currentEpisodeID) }

    if podcastEpisode.episode.currentTime != CMTime.zero {
      seek(to: podcastEpisode.episode.currentTime)
    } else {
      setCurrentTime(CMTime.zero)
    }
  }

  private func clearOnDeck() {
    currentEpisodeID = nil
    setCurrentTime(CMTime.zero)
    nowPlayingInfo = nil
    Task { await playState.setOnDeck(nil, accessKey) }
    Task(priority: .utility) { Persistence.currentEpisodeID.save(nil) }
  }

  private func setCurrentTime(_ currentTime: CMTime) {
    nowPlayingInfo?.currentTime(currentTime)
    Task { await playState.setCurrentTime(currentTime, accessKey) }
    Task(priority: .utility) {
      guard let currentEpisodeID = self.currentEpisodeID else { return }

      try await repo.updateCurrentTime(currentEpisodeID, currentTime)
    }
  }

  // MARK: - Private Helpers

  private func observeNextEpisode() async throws {
    for try await nextPodcastEpisode in observatory.nextPodcastEpisode()
    where nextPodcastEpisode != self.nextPodcastEpisode?.podcastEpisode {
      if let podcastEpisode = nextPodcastEpisode {
        do {
          let (avAsset, duration) = try await loadAsset(for: podcastEpisode.episode.media)
          self.nextPodcastEpisode = PodcastEpisodeWithDuration(
            podcastEpisode: podcastEpisode,
            duration: duration
          )
          // TODO: Add avAsset to our avPlayer
        } catch {
          self.nextPodcastEpisode = nil
          // TODO: Remove episode from queue since it can't be loaded, and report error
        }
      } else {
        self.nextPodcastEpisode = nil
        // TODO: Nothing in queue, clear any entry except the one playing
      }
    }
  }

  private func loadAsset(for mediaURL: MediaURL) async throws -> (AVURLAsset, CMTime) {
    let avAsset = AVURLAsset(url: mediaURL.rawValue)
    let (isPlayable, duration) = try await avAsset.load(.isPlayable, .duration)

    guard isPlayable
    else { throw Err.msg("\(mediaURL) is not playable") }

    return (avAsset, duration)
  }

  // MARK: - Private Tracking

  private func setStatus(_ status: PlayState.Status) {
    guard status != _status else { return }

    nowPlayingInfo?.playing(status.playing)
    Task { await playState.setStatus(status, accessKey) }
    _status = status
  }

  private func startTracking() {
    addKVObservers()
    addTimeObserver()
    startCommandCenter()
    startInterruptionNotifications()
    startPlayToEndNotifications()
  }

  private func stopTracking() {
    removeKVObservers()
    removeTimeObserver()
    stopCommandCenter()
    stopInterruptionNotifications()
    stopPlayToEndNotifications()
  }

  private func addTimeObserver() {
    removeTimeObserver()
    self.timeObserver = avPlayer.addPeriodicTimeObserver(
      forInterval: CMTime.inSeconds(1),
      queue: .global(qos: .utility)
    ) { currentTime in
      Task { [unowned self] in
        await setCurrentTime(currentTime)
      }
    }
  }

  private func removeTimeObserver() {
    if let timeObserver = self.timeObserver {
      avPlayer.removeTimeObserver(timeObserver)
      self.timeObserver = nil
    }
  }

  private func startCommandCenter() {
    stopCommandCenter()
    commandCenter.start()
    self.commandObservingTask = Task {
      for await command in commandCenter.commands() {
        if Task.isCancelled { break }
        switch command {
        case .play:
          play()
        case .pause:
          pause()
        case .togglePlayPause:
          if status.playing { pause() } else { play() }
        case .skipForward(let interval):
          seekForward(CMTime.inSeconds(interval))
        case .skipBackward(let interval):
          seekBackward(CMTime.inSeconds(interval))
        case .playbackPosition(let position):
          seek(to: CMTime.inSeconds(position))
        }
      }
    }
  }

  private func stopCommandCenter() {
    commandCenter.stop()
    if let commandObservingTask = self.commandObservingTask {
      commandObservingTask.cancel()
      self.commandObservingTask = nil
    }
  }

  private func startInterruptionNotifications() {
    stopInterruptionNotifications()
    self.interruptionObservingTask = Task {
      for await notification in notificationCenter.notifications(
        named: AVAudioSession.interruptionNotification
      ) {
        if Task.isCancelled { break }
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

  private func stopInterruptionNotifications() {
    if let interruptionObservingTask = self.interruptionObservingTask {
      interruptionObservingTask.cancel()
      self.interruptionObservingTask = nil
    }
  }

  private func startPlayToEndNotifications() {
    stopPlayToEndNotifications()
    self.playToEndObservingTask = Task {
      for await _ in notificationCenter.notifications(
        named: AVPlayerItem.didPlayToEndTimeNotification
      ) {
        if Task.isCancelled { break }
        if let currentEpisodeID = self.currentEpisodeID {
          do {
            try await repo.markComplete(currentEpisodeID)
          } catch {}
        }
        // TODO: Set new episode on deck
        print("episode finished: \(String(describing: self.currentEpisodeID))")
      }
    }
  }

  private func stopPlayToEndNotifications() {
    if let playToEndObservingTask = self.playToEndObservingTask {
      playToEndObservingTask.cancel()
      self.playToEndObservingTask = nil
    }
  }

  private func addKVObservers() {
    removeKVObservers()
    keyValueObservers.append(
      avPlayer.observe(
        \.timeControlStatus,
        options: [.initial, .new],
        changeHandler: { [unowned self] playerItem, _ in
          switch playerItem.timeControlStatus {
          case AVPlayer.TimeControlStatus.paused:
            Task { await self.setStatus(.paused) }
          case AVPlayer.TimeControlStatus.playing:
            Task { await self.setStatus(.playing) }
          case AVPlayer.TimeControlStatus.waitingToPlayAtSpecifiedRate:
            Task { await self.setStatus(.waiting) }
          @unknown default:
            fatalError("Time control status unknown?")
          }
        }
      )
    )
  }

  private func removeKVObservers() {
    for keyValueObserver in keyValueObservers { keyValueObserver.invalidate() }
    keyValueObservers.removeAll(keepingCapacity: true)
  }
}
