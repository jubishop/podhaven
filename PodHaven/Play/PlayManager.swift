// Copyright Justin Bishop, 2024

import AVFoundation
import Foundation
import SwiftUI

struct PlayManagerAccessKey { fileprivate init() {} }

@globalActor
final actor PlayActor: Sendable { static let shared = PlayActor() }

@PlayActor final class PlayManager: Sendable {
  static let shared = PlayManager()

  // MARK: - State Management

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
  private var episodeID: Int64?
  private var avPlayer = AVQueuePlayer()
  private var avPlayerItem = AVPlayerItem(url: URL.placeholder)
  private var nowPlayingInfo: NowPlayingInfo?
  private var commandCenter: CommandCenter
  private var commandObservingTask: Task<Void, Never>?
  private var interruptionObservingTask: Task<Void, Never>?
  private var currentItemObserver: NSKeyValueObservation?
  private var keyValueObservers = [NSKeyValueObservation](capacity: 1)
  private var timeObserver: Any?

  // MARK: - Convenience Getters

  private var audioSession: AVAudioSession { AVAudioSession.sharedInstance() }
  private var notificationCenter: NotificationCenter {
    NotificationCenter.default
  }

  // MARK: - Initialization

  private init() {
    commandCenter = CommandCenter(accessKey)
    avPlayer.actionAtItemEnd = .advance
  }

  func resume() async {
    currentItemObserver = avPlayer.observe(
      \.currentItem,
      options: .new,
      changeHandler: { [unowned self] currentItem, change in
        // TODO: Add next item in queue to our AVQueuePlayer
        // TODO: Observe queue changes and if first item is added, add it.
        print("current item is: \(String(describing: change.newValue))")
      }
    )

    do {
      guard let episodeID: Int64 = Persistence.currentEpisodeID.load(),
        let podcastEpisode = try await Repo.shared.db.read({ db in
          try Episode
            .filter(id: episodeID)
            .including(required: Episode.podcast)
            .asRequest(of: PodcastEpisode.self)
            .fetchOne(db)
        })
      else { return }

      await load(podcastEpisode)
    } catch {
      // Do nothing
    }
  }

  // MARK: - Loading

  func load(_ podcastEpisode: PodcastEpisode) async {
    // TODO: Remove item from queue
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
      guard isPlayable else {
        throw PlaybackError.notPlayable(podcastEpisode.episode)
      }
      duration = loadedDuration
      try audioSession.setActive(true)
    } catch {
      await Alert.shared("Can't play \(podcastEpisode.episode.toString)")
      stop()
      return
    }

    avPlayerItem = AVPlayerItem(asset: avAsset)
    avPlayer.replaceCurrentItem(with: avPlayerItem)

    await setOnDeck(podcastEpisode, duration)
    if podcastEpisode.episode.currentTime != CMTime.zero {
      seek(to: podcastEpisode.episode.currentTime)
    } else {
      setCurrentTime(CMTime.zero)
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

  func stop() {
    stopTracking()
    pause()
    if nowPlayingInfo != nil {
      setCurrentTime(CMTime.zero)
      nowPlayingInfo = nil
    }
    episodeID = nil
    status = .stopped

    do {
      try audioSession.setActive(false)
    } catch {
      Task { @MainActor in
        Alert.shared("Failed to set audio session as inactive")
      }
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

  private func setOnDeck(_ podcastEpisode: PodcastEpisode, _ duration: CMTime)
    async
  {
    episodeID = podcastEpisode.episode.id

    var image: UIImage?
    if let imageURL = podcastEpisode.episode.image
      ?? podcastEpisode.podcast.image
    {
      image = try? await Images.shared.fetchImage(imageURL)
    }
    let onDeck = OnDeck(
      feedURL: podcastEpisode.podcast.feedURL,
      guid: podcastEpisode.episode.guid,
      podcastTitle: podcastEpisode.podcast.title,
      podcastURL: podcastEpisode.podcast.link,
      episodeTitle: podcastEpisode.episode.title,
      duration: duration,
      image: image,
      mediaURL: podcastEpisode.episode.media,
      pubDate: podcastEpisode.episode.pubDate,
      key: accessKey
    )

    nowPlayingInfo = NowPlayingInfo(onDeck, accessKey)
    Task { @MainActor in PlayState.shared.setOnDeck(onDeck, accessKey) }
    Task(priority: .utility) {
      Persistence.currentEpisodeID.save(episodeID)
    }
  }

  private func setCurrentTime(_ currentTime: CMTime) {
    nowPlayingInfo?.currentTime(currentTime)
    Task { @MainActor in
      PlayState.shared.setCurrentTime(currentTime, accessKey)
    }
    Task(priority: .utility) {
      guard let episodeID = self.episodeID else { return }

      try await Repo.shared.updateCurrentTime(episodeID, currentTime)
    }
  }

  // MARK: - Private Tracking

  private func startTracking() {
    addKVObservers()
    addTimeObserver()
    startCommandCenter()
    startInterruptionNotifications()
  }

  private func stopTracking() {
    removeKVObservers()
    removeTimeObserver()
    stopCommandCenter()
    stopInterruptionNotifications()
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

  private func addKVObservers() {
    removeKVObservers()
    keyValueObservers.append(
      avPlayer.observe(
        \.timeControlStatus,
        options: .new,
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
