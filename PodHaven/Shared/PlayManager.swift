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
      case .active, .playing, .paused: return true
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

  static func configureAudioSession() async {
    do {
      try AVAudioSession.sharedInstance()
        .setCategory(
          .playback,
          mode: .spokenAudio,
          policy: .longFormAudio
        )
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
  private let nowPlayingInfo = NowPlayingInfo(PlayManagerAccessKey())
  private let commandCenter = CommandCenter(PlayManagerAccessKey())
  private let loadingSemaphor = AsyncSemaphore(value: 1)
  private var commandObservingTask: Task<Void, Never>?
  private var keyValueObservers = [NSKeyValueObservation](capacity: 1)
  private var timeObserver: Any?

  // MARK: - Private Variables

  private var avPlayer = AVPlayer()
  private var avPlayerItem = AVPlayerItem(url: URL.placeholder)
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

    removeObservers()
    pause()
    status = .loading

    let avAsset = AVURLAsset(url: url)
    let (isPlayable, duration) = try await avAsset.load(.isPlayable, .duration)
    guard isPlayable else {
      throw PlaybackError.notPlayable(url)
    }

    do {
      try AVAudioSession.sharedInstance().setActive(true)
    } catch {
      Task { @MainActor in Alert.shared("Failed to set audio session active") }
      throw PlaybackError.notActive
    }

    setPodcastEpisode(podcastEpisode)
    setDuration(duration)

    avPlayerItem = AVPlayerItem(asset: avAsset)
    avPlayer.replaceCurrentItem(with: avPlayerItem)

    status = .active
    addObservers()
    startCommandCenter()
  }

  func play() {
    guard status.playable else { return }
    avPlayer.play()
  }

  func pause() {
    avPlayer.pause()
  }

  func stop() {
    stopCommandCenter()
    removeObservers()
    status = .stopped
    pause()
    setCurrentTime(Self.CMTimeInSeconds(0))

    do {
      try AVAudioSession.sharedInstance().setActive(false)
    } catch {
      Task { @MainActor in
        Alert.shared("Failed to set audio session as inactive")
      }
    }
  }

  func seekForward(_ duration: CMTime = CMTimeInSeconds(10)) {
    seek(to: avPlayer.currentTime() + duration)
  }

  func seekBackward(_ duration: CMTime = CMTimeInSeconds(10)) {
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

  // MARK: - Private Methods

  private func setPodcastEpisode(_ podcastEpisode: PodcastEpisode) {
    nowPlayingInfo.onDeck(podcastEpisode)
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

  private func startCommandCenter() {
    commandCenter.begin()
    self.commandObservingTask = Task { @PlayActor in
      for await command in commandCenter.commands() {
        if Task.isCancelled {
          break
        }
        switch command {
        case .play:
          play()
        case .pause:
          pause()
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

  private func addObservers() {
    removeObservers()

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
    addTimeObserver()
  }

  private func removeObservers() {
    for keyValueObserver in keyValueObservers { keyValueObserver.invalidate() }
    keyValueObservers.removeAll(keepingCapacity: true)
    removeTimeObserver()
  }

  private func addTimeObserver() {
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
