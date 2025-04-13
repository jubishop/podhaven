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
  @ObservationIgnored @LazyInjected(\.queue) private var queue
  @ObservationIgnored @LazyInjected(\.repo) private var repo

  private let accessKey = PlayManagerAccessKey()
  private var _status: PlayState.Status = .stopped
  private var status: PlayState.Status {
    get { _status }
    set {
      guard newValue != _status else { return }

      _status = newValue
      nowPlayingInfo?.playing(newValue.playing)
      Task { await playState.setStatus(newValue, accessKey) }
    }
  }
  var episodeID: Episode.ID?
  private var avPlayer = AVPlayer()
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
  }

  func resume() async {
    do {
      guard let episodeID: Episode.ID = Persistence.currentEpisodeID.load(),
        let podcastEpisode = try await repo.episode(episodeID)
      else { return }

      try await load(podcastEpisode)
    } catch {
      // Do nothing
    }
  }

  // MARK: - Loading

  func load(_ podcastEpisode: PodcastEpisode) async throws {
    if status == .loading { return }

    stopTracking()
    pause()
    status = .loading

    let avAsset = AVURLAsset(url: podcastEpisode.episode.media.rawValue)

    let duration: CMTime
    do {
      let (isPlayable, loadedDuration) = try await avAsset.load(.isPlayable, .duration)
      guard isPlayable
      else { throw Err.msg("\(podcastEpisode.episode.toString) is not playable") }

      duration = loadedDuration
      try audioSession.setActive(true)
    } catch {
      await reload()
      throw Err.msg("Can't play \(podcastEpisode.episode.toString)")
    }

    let avPlayerItem = AVPlayerItem(asset: avAsset)
    avPlayer.replaceCurrentItem(with: avPlayerItem)

    do {
      try await setOnDeck(podcastEpisode, duration)
    } catch {
      await reload()
      throw Err.msg("Failed to set \(podcastEpisode.episode.toString) on deck")
    }

    status = .active
    startTracking()
  }

  private func reload() async {
    status = .stopped

    let episodeID = self.episodeID
    self.episodeID = nil

    guard let episodeID = episodeID, let podcastEpisode = try? await repo.episode(episodeID)
    else { return }

    try? await load(podcastEpisode)
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

  private func setOnDeck(_ podcastEpisode: PodcastEpisode, _ duration: CMTime) async throws {
    guard podcastEpisode.id != episodeID else { return }

    if let episodeID = self.episodeID {
      try await queue.unshift(episodeID)
    }
    try await queue.dequeue(podcastEpisode.id)

    self.episodeID = podcastEpisode.id

    let imageURL = podcastEpisode.episode.image ?? podcastEpisode.podcast.image
    let onDeck = OnDeck(
      feedURL: podcastEpisode.podcast.feedURL,
      guid: podcastEpisode.episode.guid,
      podcastTitle: podcastEpisode.podcast.title,
      podcastURL: podcastEpisode.podcast.link,
      episodeTitle: podcastEpisode.episode.title,
      duration: duration,
      image: try await images.fetchImage(imageURL),
      media: podcastEpisode.episode.media,
      pubDate: podcastEpisode.episode.pubDate,
      key: accessKey
    )

    nowPlayingInfo = NowPlayingInfo(onDeck, accessKey)
    Task { await playState.setOnDeck(onDeck, accessKey) }
    Task(priority: .utility) { Persistence.currentEpisodeID.save(episodeID) }

    if podcastEpisode.episode.currentTime != CMTime.zero {
      seek(to: podcastEpisode.episode.currentTime)
    } else {
      setCurrentTime(CMTime.zero)
    }
  }

  private func clearOnDeck() {
    episodeID = nil
    setCurrentTime(CMTime.zero)
    nowPlayingInfo = nil
    Task { await playState.setOnDeck(nil, accessKey) }
    Task(priority: .utility) { Persistence.currentEpisodeID.save(nil) }
  }

  private func setCurrentTime(_ currentTime: CMTime) {
    nowPlayingInfo?.currentTime(currentTime)
    Task { await playState.setCurrentTime(currentTime, accessKey) }
    Task(priority: .utility) {
      guard let episodeID = self.episodeID else { return }

      try await repo.updateCurrentTime(episodeID, currentTime)
    }
  }

  // MARK: - Private Tracking

  private func setStatus(_ status: PlayState.Status) {
    self.status = status
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
        if let episodeID = self.episodeID {
          do {
            try await repo.markComplete(episodeID)
          } catch {}
        }
        clearOnDeck()
        if let nextEpisode = try? await repo.nextEpisode() {
          Task {
            try await load(nextEpisode)
            play()
          }
        }
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
