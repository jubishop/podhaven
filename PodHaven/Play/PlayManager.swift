// Copyright Justin Bishop, 2025

import AVFoundation
import Factory
import Foundation
import GRDB

struct PlayManagerAccessKey { fileprivate init() {} }

@globalActor
final actor PlayActor: Sendable { static let shared = PlayActor() }

extension Container {
  var playManager: Factory<Task<PlayManager, Never>> {
    Factory(self) { Task { await PlayManager() } }.scope(.singleton)
  }
}

@PlayActor final class PlayManager: Sendable {
  // MARK: - State Management

  @ObservationIgnored @Injected(\.repo) private var repo
  @ObservationIgnored @Injected(\.queue) private var queue
  @ObservationIgnored @Injected(\.images) private var images

  private let accessKey = PlayManagerAccessKey()
  private var _status: PlayState.Status = .stopped
  private var status: PlayState.Status {
    get { _status }
    set {
      guard newValue != _status else { return }
      _status = newValue
      nowPlayingInfo?.playing(newValue.playing)
      Task { @MainActor in PlayState.shared.setStatus(newValue, accessKey) }
    }
  }
  var episodeID: Int64? { onDeck?.episode.id }
  private var avPlayer = AVPlayer()
  private var nowPlayingInfo: NowPlayingInfo?
  private var onDeck: PodcastEpisode?
  private var upNext: PodcastEpisode?
  private var commandCenter: CommandCenter
  private var commandObservingTask: Task<Void, Never>?
  private var interruptionObservingTask: Task<Void, Never>?
  private var playToEndObservingTask: Task<Void, Never>?
  private var keyValueObservers = [NSKeyValueObservation](capacity: 1)
  private var timeObserver: Any?

  // MARK: - Convenience Getters

  private var audioSession: AVAudioSession { AVAudioSession.sharedInstance() }
  private var notificationCenter: NotificationCenter {
    NotificationCenter.default
  }

  // MARK: - Initialization

  fileprivate init() {
    commandCenter = CommandCenter(accessKey)
  }

  func resume() async {
    do {
      guard let episodeID: Int64 = Persistence.currentEpisodeID.load(),
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

    let avAsset = AVURLAsset(url: podcastEpisode.episode.media)

    let duration: CMTime
    do {
      let (isPlayable, loadedDuration) = try await avAsset.load(
        .isPlayable,
        .duration
      )
      guard isPlayable
      else { throw Err.msg("\(podcastEpisode.episode.toString) is not playable") }

      duration = loadedDuration
      try audioSession.setActive(true)
    } catch {
      try stop()
      throw Err.msg("Can't play \(podcastEpisode.episode.toString)")
    }

    let avPlayerItem = AVPlayerItem(asset: avAsset)
    avPlayer.replaceCurrentItem(with: avPlayerItem)

    do {
      try await setOnDeck(podcastEpisode, duration)
    } catch {
      try stop()
      throw Err.msg("Failed to set \(podcastEpisode.episode.toString) on deck")
    }

    status = .active
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

  func stop() throws {
    stopTracking()
    pause()
    clearOnDeck()
    status = .stopped

    do {
      try audioSession.setActive(false)
    } catch {
      throw Err.msg("Failed to set audio session as inactive")
    }
  }

  // MARK: - Seeking

  func seekForward(_ duration: CMTime) {
    seek(to: avPlayer.currentTime() + duration)
  }

  func seekBackward(_ duration: CMTime) {
    seek(to: avPlayer.currentTime() - duration)
  }

  func seek(to time: CMTime) {
    let observingTime = removeTimeObserver()
    setCurrentTime(time)
    avPlayer.seek(to: time) { [unowned self] completed in
      if completed, observingTime {
        Task { @PlayActor in addTimeObserver() }
      }
    }
  }

  // MARK: - Private State Management

  private func setOnDeck(_ podcastEpisode: PodcastEpisode, _ duration: CMTime) async throws {
    guard podcastEpisode != onDeck else { return }

    if let episodeID = onDeck?.id {
      try await queue.unshift(episodeID)
    }

    try await queue.dequeue(podcastEpisode.id)
    onDeck = podcastEpisode

    let imageURL = podcastEpisode.episode.image ?? podcastEpisode.podcast.image
    let onDeck = OnDeck(
      feedURL: podcastEpisode.podcast.feedURL,
      guid: podcastEpisode.episode.guid,
      podcastTitle: podcastEpisode.podcast.title,
      podcastURL: podcastEpisode.podcast.link,
      episodeTitle: podcastEpisode.episode.title,
      duration: duration,
      image: try await images.fetchImage(imageURL),
      mediaURL: podcastEpisode.episode.media,
      pubDate: podcastEpisode.episode.pubDate,
      key: accessKey
    )

    nowPlayingInfo = NowPlayingInfo(onDeck, accessKey)
    Task { @MainActor in PlayState.shared.setOnDeck(onDeck, accessKey) }
    Task(priority: .utility) {
      Persistence.currentEpisodeID.save(episodeID)
    }

    if podcastEpisode.episode.currentTime != CMTime.zero {
      seek(to: podcastEpisode.episode.currentTime)
    } else {
      setCurrentTime(CMTime.zero)
    }
  }

  private func clearOnDeck() {
    onDeck = nil
    if nowPlayingInfo != nil {
      setCurrentTime(CMTime.zero)
      nowPlayingInfo = nil
    }
    Task { @MainActor in PlayState.shared.setOnDeck(nil, accessKey) }
    Task(priority: .utility) {
      Persistence.currentEpisodeID.save(nil)
    }
  }

  private func setCurrentTime(_ currentTime: CMTime) {
    nowPlayingInfo?.currentTime(currentTime)
    Task { @MainActor in
      PlayState.shared.setCurrentTime(currentTime, accessKey)
    }
    Task(priority: .utility) {
      guard let episodeID = self.episodeID else { return }

      try await repo.updateCurrentTime(episodeID, currentTime)
    }
  }

  // MARK: - Private Tracking

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
    timeObserver = avPlayer.addPeriodicTimeObserver(
      forInterval: CMTime.inSeconds(1),
      queue: .global(qos: .utility)
    ) { currentTime in
      Task { @PlayActor [unowned self] in setCurrentTime(currentTime) }
    }
  }

  @discardableResult
  private func removeTimeObserver() -> Bool {
    if let timeObserver = timeObserver {
      avPlayer.removeTimeObserver(timeObserver)
      self.timeObserver = nil
      return true
    }
    return false
  }

  private func startCommandCenter() {
    stopCommandCenter()
    commandCenter.start()
    self.commandObservingTask = Task { @PlayActor in
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
    self.interruptionObservingTask = Task { @PlayActor in
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
        @unknown default:
          fatalError("Interruption Notification unknown?!")
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
    self.playToEndObservingTask = Task { @PlayActor in
      for await _ in notificationCenter.notifications(
        named: AVPlayerItem.didPlayToEndTimeNotification
      ) {
        if Task.isCancelled { break }
        if let episodeID = onDeck?.id {
          try? await repo.markComplete(episodeID)
        }
        clearOnDeck()
        if let nextEpisode = try? await repo.nextEpisode() {
          Task { @PlayActor in
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
            Task { @PlayActor in status = .paused }
          case AVPlayer.TimeControlStatus.playing:
            Task { @PlayActor in status = .playing }
          case AVPlayer.TimeControlStatus.waitingToPlayAtSpecifiedRate:
            Task { @PlayActor in status = .waiting }
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
