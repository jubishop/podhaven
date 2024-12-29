// Copyright Justin Bishop, 2024

import AVFoundation
import Foundation
import GRDB
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
  var episodeID: Int64? { onDeck?.episode.id }
  private var avPlayer = AVQueuePlayer()
  private var nowPlayingInfo: NowPlayingInfo?
  private var onDeck: PodcastEpisode?
  private var upNext: PodcastEpisode?
  private var commandCenter: CommandCenter
  private var commandObservingTask: Task<Void, Never>?
  private var interruptionObservingTask: Task<Void, Never>?
  private var queueObservingTask: Task<Void, Error>?
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
    if status == .loading { return }

    // TODO: place currently playing item at top of queue

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

    let avPlayerItem = AVPlayerItem(asset: avAsset)
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
    clearOnDeck()
    clearUpNext()
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
    onDeck = podcastEpisode
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

  private func setUpNext(_ podcastEpisode: PodcastEpisode) {
    // TODO: Add item to our AVQueuePlayer
    upNext = podcastEpisode
  }

  private func clearUpNext() {
    // TODO: Remove item from our AVQueuePlayer
    upNext = nil
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
    startQueueObserving()
    startInterruptionNotifications()
  }

  private func stopTracking() {
    removeKVObservers()
    removeTimeObserver()
    stopCommandCenter()
    stopQueueObserving()
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

  private func startQueueObserving() {
    stopQueueObserving()
    self.queueObservingTask = Task { @PlayActor in
      let observer =
        ValueObservation.tracking(
          Episode
            .filter(AppDB.queueOrderColumn == 0)
            .including(required: Episode.podcast)
            .asRequest(of: PodcastEpisode.self)
            .fetchOne
        )
        .removeDuplicates()
      for try await topQueueItem in observer.values(in: Repo.shared.db) {
        if Task.isCancelled { break }
        if let upNext = topQueueItem {
          self.setUpNext(upNext)
        } else {
          self.clearUpNext()
        }
      }
    }
  }

  private func stopQueueObserving() {
    if let queueObservingTask = self.queueObservingTask {
      queueObservingTask.cancel()
      self.queueObservingTask = nil
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
    keyValueObservers.append(
      avPlayer.observe(
        \.currentItem,
        options: [.initial, .new],
        changeHandler: { avPlayer, _ in
          Task { @MainActor in
            if let currentItem = avPlayer.currentItem,
              let urlAsset = currentItem.asset as? AVURLAsset
            {
              Task.detached(priority: .utility) {
                if let episode = try await Repo.shared.episode(urlAsset.url) {
                  try await Repo.shared.dequeue(episode.id)
                }
              }
            } else {
              Alert.shared.report("Could not fetch URL for current item?")
            }
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
