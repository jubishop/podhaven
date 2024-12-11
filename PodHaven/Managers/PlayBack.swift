// Copyright Justin Bishop, 2024

import AVFoundation
import Foundation

@Observable @MainActor final class PlayState: Sendable {
  static let shared = { PlayState() }()

  fileprivate(set) var isActive = false
  fileprivate(set) var isPlaying = false

  private init() {}
}

actor PlayManager: Sendable {
  // MARK: - Static Methods

  static let shared = { PlayManager() }()

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

  private var _isPlaying = false
  private var isPlaying: Bool {
    get { _isPlaying }
    set {
      if newValue != _isPlaying {
        _isPlaying = newValue
        DispatchQueue.main.sync { PlayState.shared.isPlaying = newValue }
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
        DispatchQueue.main.sync { PlayState.shared.isActive = newValue }
      }
    }
  }

  private var avPlayer = AVPlayer()
  private var avPlayerItem = AVPlayerItem(url: URL.placeholder)
  private var keyValueObservers: [NSKeyValueObservation] = []
  private var timeObserver: Any?

  fileprivate init() {}

  // MARK: - Public Methods

  func start(_ url: URL) {
    load(url)
    play()
  }

  func load(_ url: URL) {
    isActive = true
    isPlaying = false
    avPlayerItem = AVPlayerItem(url: url)
    avPlayer.replaceCurrentItem(with: avPlayerItem)
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

  // MARK: - Private Methods

  private func reset(from error: Error?) {
    stop()
    avPlayer = AVPlayer()
    avPlayerItem = AVPlayerItem(url: URL.placeholder)
    Task { @MainActor in
      Alert.shared(
        "Playback encountered an error: \(String(describing: error))"
      )
    }
  }

  private func addObservers() {
    removeObservers()

    keyValueObservers.append(
      avPlayerItem.observe(
        \.duration,
        options: [.initial, .new]
      ) { _, change in
        if let duration = change.newValue {
          print("Duration is: \(duration)")
        }
      }
    )

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
      forInterval: CMTime(seconds: 1, preferredTimescale: 100),
      queue: .global(qos: .utility)
    ) { time in
      print("Time is: \(time)")
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
