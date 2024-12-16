// Copyright Justin Bishop, 2024

import AVFoundation
import Foundation

@Observable @MainActor final class PlayState: Sendable {
  static let shared = PlayState()

  fileprivate(set) var isLoading = false
  fileprivate(set) var isActive = false
  fileprivate(set) var isPlaying = false
  fileprivate(set) var duration = CMTime.zero
  fileprivate(set) var currentTime = CMTime.zero
  fileprivate(set) var onDeck: PodcastEpisode?
  private init() {}
}

@globalActor
final actor PlayActor: Sendable { static let shared = PlayActor() }

@PlayActor
final class PlayManager: Sendable {
  // MARK: - Static Methods

  static let shared = PlayManager()

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

  static func CMTime(seconds: Double) -> CMTime {
    CoreMedia.CMTime(seconds: seconds, preferredTimescale: 60)
  }

  // MARK: - State Management

  private var _isLoading = false
  private var isLoading: Bool {
    get { _isLoading }
    set {
      if newValue != _isLoading {
        _isLoading = newValue
        Task { @MainActor in PlayState.shared.isLoading = newValue }
        Task { @MPActor in MPTransport.shared.isLoading = newValue }
      }
    }
  }
  private var _isPlaying = false
  private var isPlaying: Bool {
    get { _isPlaying }
    set {
      if newValue != _isPlaying {
        _isPlaying = newValue
        Task { @MainActor in PlayState.shared.isPlaying = newValue }
        Task { @MPActor in MPTransport.shared.isPlaying = newValue }
      }
    }
  }
  private var _isActive = false
  private var isActive: Bool {
    get { _isActive }
    set {
      if newValue != _isActive {
        do {
          try AVAudioSession.sharedInstance().setActive(newValue)
        } catch {
          Task { @MainActor in
            Alert.shared("Failed to activate audio session")
          }
        }
        _isActive = newValue
        Task { @MainActor in PlayState.shared.isActive = newValue }
        Task { @MPActor in MPTransport.shared.isActive = newValue }
      }
    }
  }

  // MARK: - Private Variables

  private var avPlayer = AVPlayer()
  private var avPlayerItem = AVPlayerItem(url: URL.placeholder)
  private var timeObserver: Any?
  init() {}

  // MARK: - Public Methods

  func start(_ podcastEpisode: PodcastEpisode) async throws {
    try await load(podcastEpisode)
    play()
  }

  func load(_ podcastEpisode: PodcastEpisode) async throws {
    guard let url = podcastEpisode.episode.media else {
      throw PlaybackError.noURL(podcastEpisode.episode)
    }
    guard !isLoading else { return }
    defer { isLoading = false }
    isLoading = true

    let avAsset = AVURLAsset(url: url)
    let (isPlayable, duration) = try await avAsset.load(.isPlayable, .duration)
    guard isPlayable else {
      throw PlaybackError.notPlayable(url)
    }

    pause()
    await setPodcastEpisode(podcastEpisode)
    await setDuration(duration)
    avPlayerItem = AVPlayerItem(asset: avAsset)
    avPlayer.replaceCurrentItem(with: avPlayerItem)
    isActive = true
  }

  func play() {
    guard isActive && !isPlaying else { return }
    isPlaying = true

    avPlayer.play()
    addObservers()
  }

  func pause() {
    guard isPlaying else { return }
    isPlaying = false

    removeObservers()
    avPlayer.pause()
  }

  func stop() {
    pause()
    isActive = false
  }

  func seekForward(_ duration: CMTime = CMTime(seconds: 10)) async {
    guard !isLoading, isActive else { return }
    await seek(to: avPlayer.currentTime() + duration)
  }

  func seekBackward(_ duration: CMTime = CMTime(seconds: 10)) async {
    guard !isLoading, isActive else { return }
    await seek(to: avPlayer.currentTime() - duration)
  }

  func seek(to time: CMTime) async {
    guard !isLoading, isActive else { return }
    removeTimeObserver()
    await setCurrentTime(time)
    avPlayer.seek(to: time) { [unowned self] completed in
      if completed {
        Task { @PlayActor in
          self.addTimeObserver()
        }
      }
    }
  }

  // MARK: - Private Methods

  private func setPodcastEpisode(_ podcastEpisode: PodcastEpisode) async {
    await Task { @MainActor in PlayState.shared.onDeck = podcastEpisode }.value
    await Task { @MPActor in MPTransport.shared.onDeck(podcastEpisode) }.value
  }

  private func setDuration(_ duration: CMTime) async {
    await Task { @MainActor in PlayState.shared.duration = duration }.value
    await Task { @MPActor in MPTransport.shared.duration(duration) }.value
  }

  private func setCurrentTime(_ currentTime: CMTime) async {
    await Task { @MainActor in
      PlayState.shared.currentTime = currentTime
    }
    .value
  }

  private func addObservers() {
    removeObservers()
    addTimeObserver()
  }

  private func removeObservers() {
    removeTimeObserver()
  }

  private func addTimeObserver() {
    timeObserver = avPlayer.addPeriodicTimeObserver(
      forInterval: Self.CMTime(seconds: 1),
      queue: .global(qos: .utility)
    ) { currentTime in
      Task { [unowned self] in await self.setCurrentTime(currentTime) }
    }
  }

  private func removeTimeObserver() {
    if let timeObserver = timeObserver {
      avPlayer.removeTimeObserver(timeObserver)
      self.timeObserver = nil
    }
  }
}
