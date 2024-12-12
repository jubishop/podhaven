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

final actor PlayManager: Sendable {
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

  // MARK: - State Management

  private var _isLoading = false
  private var isLoading: Bool {
    get { _isLoading }
    set {
      if newValue != _isLoading {
        _isLoading = newValue
        Task { @MainActor in PlayState.shared.isLoading = newValue }
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
      }
    }
  }

  // MARK: - Private Variables

  private var avPlayer = AVPlayer()
  private var avPlayerItem = AVPlayerItem(url: URL.placeholder)
  private var keyValueObservers: [NSKeyValueObservation] = []
  private var timeObserver: Any?
  fileprivate init() {}

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

  func seekForward(
    _ duration: CMTime = CMTime(seconds: 10, preferredTimescale: 60)
  ) {
    guard !isLoading, isActive else { return }
    seek(to: avPlayer.currentTime() + duration)
  }

  func seekBackward(
    _ duration: CMTime = CMTime(seconds: 10, preferredTimescale: 60)
  ) {
    guard !isLoading, isActive else { return }
    seek(to: avPlayer.currentTime() - duration)
  }

  func seek(to time: CMTime) {
    avPlayer.seek(to: time)
  }

  // MARK: - Private Methods

  private func reset(from error: Error?) {
    stop()
    avPlayer = AVPlayer()
    avPlayerItem = AVPlayerItem(url: URL.placeholder)
    Task { @MainActor in
      Alert.shared("Playback status failure: \(String(describing: error))")
    }
  }

  private func setPodcastEpisode(_ podcastEpisode: PodcastEpisode) async {
    await Task { @MainActor in PlayState.shared.onDeck = podcastEpisode }.value
  }

  private func setDuration(_ duration: CMTime) async {
    await Task { @MainActor in PlayState.shared.duration = duration }.value
  }

  private func addObservers() {
    removeObservers()

    keyValueObservers.append(
      avPlayerItem.observe(
        \.status,
        options: [.initial, .new]
      ) { [unowned self] _, change in
        if change.newValue == .failed {
          Task { await self.reset(from: avPlayerItem.error) }
        }
      }
    )
    keyValueObservers.append(
      avPlayer.observe(
        \.status,
        options: [.initial, .new]
      ) { [unowned self] _, change in
        if change.newValue == .failed {
          Task { await self.reset(from: avPlayer.error) }
        }
      }
    )

    timeObserver = avPlayer.addPeriodicTimeObserver(
      forInterval: CMTime(seconds: 1, preferredTimescale: 60),
      queue: .global(qos: .utility)
    ) { currentTime in
      Task { @MainActor in PlayState.shared.currentTime = currentTime }
    }
  }

  private func removeObservers() {
    if let timeObserver = timeObserver {
      avPlayer.removeTimeObserver(timeObserver)
      self.timeObserver = nil
    }
    for keyValueObserver in keyValueObservers {
      keyValueObserver.invalidate()
    }
    keyValueObservers = []
  }
}
