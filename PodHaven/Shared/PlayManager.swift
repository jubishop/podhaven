// Copyright Justin Bishop, 2024

import AVFoundation
import Foundation
import Semaphore

@dynamicMemberLookup
@Observable @MainActor final class PlayState: Sendable {
  static let shared = PlayState()

  // MARK: - Meta

  static subscript<T>(dynamicMember keyPath: KeyPath<PlayState, T>) -> T {
    shared[keyPath: keyPath]
  }

  subscript<T>(dynamicMember keyPath: KeyPath<PlayState.Status, T>) -> T {
    status[keyPath: keyPath]
  }

  // MARK:- State Management

  enum Status: Sendable {
    case loading, active, playing, paused, stopped, waiting

    var playable: Bool {
      switch self {
      case .active, .playing, .paused, .waiting: return true
      default: return false
      }
    }

    var loading: Bool { self == .loading }
    var active: Bool { self == .active }
    var playing: Bool { self == .playing }
    var paused: Bool { self == .paused }
    var stopped: Bool { self == .stopped }
    var waiting: Bool { self == .waiting }
  }

  fileprivate(set) var status: Status = .stopped
  fileprivate(set) var duration = CMTime.zero
  fileprivate(set) var currentTime = CMTime.zero
  fileprivate(set) var onDeck: PodcastEpisode?
  private init() {}
}

struct PlayManagerAccessKey { fileprivate init() {} }

@globalActor
final actor PlayActor: Sendable { static let shared = PlayActor() }

@PlayActor final class PlayManager: Sendable {
  static let shared = PlayManager()

  // MARK: - Static Methods

  private static var audioSession: AVAudioSession {
    AVAudioSession.sharedInstance()
  }

  static func configureAudioSession() async {
    do {
      try audioSession.setCategory(
        .playback,
        mode: .spokenAudio,
        policy: .longFormAudio
      )
      try audioSession.setMode(.spokenAudio)
    } catch {
      await Alert.shared("Failed to set the audio session configuration")
    }
  }

  static func CMTimeInSeconds(_ seconds: Double) -> CMTime {
    CMTime(seconds: seconds, preferredTimescale: 60)
  }

  // MARK: - State Management

  private var _status: PlayState.Status = .stopped
  private var status: PlayState.Status {
    get { _status }
    set {
      guard newValue != _status else { return }
      _status = newValue
      nowPlayingInfo.status = newValue
      Task { @MainActor in PlayState.shared.status = newValue }
    }
  }
  private var avPlayer = AVPlayer()
  private var avPlayerItem = AVPlayerItem(url: URL.placeholder)
  private var nowPlayingInfo = NowPlayingInfo(PlayManagerAccessKey())
  private var commandCenter = CommandCenter(PlayManagerAccessKey())
  private let loadingSemaphor = AsyncSemaphore(value: 1)
  private var commandObservingTask: Task<Void, Never>?
  private var notificationObservingTask: Task<Void, Never>?
  private var keyValueObservers = [NSKeyValueObservation](capacity: 1)
  private var timeObserver: Any?

  // MARK: - Convenience Getters

  private var audioSession: AVAudioSession { Self.audioSession }
  private var notificationCenter: NotificationCenter {
    NotificationCenter.default
  }
  private init() {}

  // MARK: - Public Methods

  func start(_ podcastEpisode: PodcastEpisode) async throws {
    try await load(podcastEpisode)
    play()
  }

  func load(_ podcastEpisode: PodcastEpisode) async throws {
    guard let url = podcastEpisode.episode.media else {
      throw PlaybackError.noURL(podcastEpisode.episode)
    }
    await loadingSemaphor.wait()
    defer { loadingSemaphor.signal() }

    rewind()
    status = .loading

    let avAsset = AVURLAsset(url: url)
    let (isPlayable, duration) = try await avAsset.load(.isPlayable, .duration)
    guard isPlayable else {
      throw PlaybackError.notPlayable(url)
    }

    do {
      try audioSession.setActive(true)
    } catch {
      Task { @MainActor in Alert.shared("Failed to set audio session active") }
      throw PlaybackError.notActive
    }

    await setPodcastEpisode(podcastEpisode)
    setDuration(duration)

    avPlayerItem = AVPlayerItem(asset: avAsset)
    avPlayer.replaceCurrentItem(with: avPlayerItem)

    status = .active
    addObservers()
    startIntegrations()
  }

  func play() {
    guard status.playable else { return }
    avPlayer.play()
  }

  func pause() {
    avPlayer.pause()
  }

  func stop() {
    stopIntegrations()
    rewind()
    status = .stopped

    do {
      try audioSession.setActive(false)
    } catch {
      Task { @MainActor in
        Alert.shared("Failed to set audio session as inactive")
      }
    }
  }

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
        Task { @PlayActor in addTimeObserver() }
      }
    }
  }

  // MARK: - Private State Management

  private func rewind() {
    removeObservers()
    pause()
    setCurrentTime(CMTime.zero)
  }

  private func setPodcastEpisode(_ podcastEpisode: PodcastEpisode) async {
    nowPlayingInfo.podcastEpisode = podcastEpisode
    await nowPlayingInfo.onDeck()
    Task { @MainActor in PlayState.shared.onDeck = podcastEpisode }
  }

  private func setDuration(_ duration: CMTime) {
    nowPlayingInfo.duration(duration)
    Task { @MainActor in PlayState.shared.duration = duration }
  }

  private func setCurrentTime(_ currentTime: CMTime) {
    nowPlayingInfo.currentTime(currentTime)
    Task { @MainActor in PlayState.shared.currentTime = currentTime }
  }

  // MARK: - Private Observers / Integrators

  private func startIntegrations() {
    startCommandCenter()
    startInterruptionNotifications()
  }

  private func stopIntegrations() {
    stopCommandCenter()
    stopInterruptionNotifications()
  }

  private func startCommandCenter() {
    stopCommandCenter()
    commandCenter.begin()
    self.commandObservingTask = Task { @PlayActor in
      for await command in commandCenter.commands() {
        if Task.isCancelled { break }
        switch command {
        case .play:
          play()
        case .pause:
          pause()
        case .skipForward(let interval):
          seekForward(Self.CMTimeInSeconds(interval))
        case .skipBackward(let interval):
          seekBackward(Self.CMTimeInSeconds(interval))
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
    self.notificationObservingTask = Task { @PlayActor in
      for await notification in notificationCenter.notifications(
        named: AVAudioSession.interruptionNotification
      ) {
        if Task.isCancelled { break }
        guard notification.name == AVAudioSession.interruptionNotification,
          let userInfo = notification.userInfo,
          let typeValue = userInfo[AVAudioSessionInterruptionTypeKey] as? UInt,
          let type = AVAudioSession.InterruptionType(rawValue: typeValue)
        else { return }

        switch type {
        case .began:
          pause()
        case .ended:
          guard
            let optionsValue = userInfo[AVAudioSessionInterruptionOptionKey]
              as? UInt
          else { return }

          let options = AVAudioSession.InterruptionOptions(
            rawValue: optionsValue
          )
          if options.contains(.shouldResume) {
            play()
          }
        @unknown default:
          break
        }
      }
    }
  }

  private func stopInterruptionNotifications() {
    if let notificationObservingTask = self.notificationObservingTask {
      notificationObservingTask.cancel()
      self.notificationObservingTask = nil
    }
  }

  private func addObservers() {
    addKVObservers()
    addTimeObserver()
  }

  private func removeObservers() {
    removeKVObservers()
    removeTimeObserver()
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

  private func addTimeObserver() {
    removeTimeObserver()
    timeObserver = avPlayer.addPeriodicTimeObserver(
      forInterval: Self.CMTimeInSeconds(1),
      queue: .global(qos: .utility)
    ) { currentTime in
      Task { @PlayActor [unowned self] in setCurrentTime(currentTime) }
    }
  }

  private func removeTimeObserver() {
    if let timeObserver = timeObserver {
      avPlayer.removeTimeObserver(timeObserver)
      self.timeObserver = nil
    }
  }
}
