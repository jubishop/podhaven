// Copyright Justin Bishop, 2024

import AVFoundation
import Foundation

@Observable @MainActor final class PlayState: Sendable {
  static let shared = { PlayState() }()

  fileprivate(set)var isActive = false
  fileprivate(set)var isPlaying = false

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

  private var isPlaying: Bool = false  // Semaphor
  private var currentURL: URL = URL.placeholder
  private var avPlayer = AVPlayer() {
    willSet {
      avPlayer.pause()
      removeObservers()
    }
  }
  private var avPlayerItem = AVPlayerItem(url: URL.placeholder) {
    willSet {
      avPlayer.pause()
      removeObservers()
    }
  }
  private var isActive = false {
    willSet {
      if newValue != isActive {
        DispatchQueue.main.sync { PlayState.shared.isActive = newValue }
        do {
          try AVAudioSession.sharedInstance().setActive(newValue)
        } catch {
          Task { @MainActor in
            Alert.shared("Failed to activate audio session")
          }
        }
      }
    }
  }
  private var durationObserver: NSKeyValueObservation?
  private var timeObserver: Any?

  fileprivate init() {}

  // MARK: - Public Methods

  func start(_ url: URL) {
    load(url)
    play()
  }

  func load(_ url: URL) {
    isPlaying = false
    DispatchQueue.main.sync { PlayState.shared.isPlaying = true }

    isActive = true
    currentURL = url
    if avPlayer.status == .failed {
      Task { @MainActor in
        await Alert.shared.report(
          """
          AVPlayer failed with message: \
          \(avPlayer.error?.localizedDescription ?? "")
          """
        )
      }
      avPlayer = AVPlayer()
    }
    avPlayerItem = AVPlayerItem(url: url)
    avPlayer.replaceCurrentItem(with: avPlayerItem)
  }

  func play() {
    guard isActive && !isPlaying else { return }
    isPlaying = true
    DispatchQueue.main.sync { PlayState.shared.isPlaying = true }

    if avPlayerItem.status == .failed {
      Task { @MainActor in
        await Alert.shared.report(
          """
          AVPlayerItem failed with message: \
          \(avPlayerItem.error?.localizedDescription ?? "")
          """
        )
      }
      avPlayerItem = AVPlayerItem(url: currentURL)
      avPlayer.replaceCurrentItem(with: avPlayerItem)
    }
    avPlayer.play()
    addObservers()
  }

  func pause() {
    guard isPlaying else { return }
    isPlaying = false
    DispatchQueue.main.sync { PlayState.shared.isPlaying = false }

    removeObservers()
    avPlayer.pause()
  }

  func stop() {
    pause()
    isActive = false
  }

  // MARK: - Private Methods

  private func addObservers() {
    removeObservers()
    durationObserver = avPlayerItem.observe(
      \.duration,
      options: [.initial, .new]
    ) { _, change in
      if let duration = change.newValue {
        print("Duration is: \(duration)")
      }
    }
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
    }
    self.timeObserver = nil
    self.durationObserver?.invalidate()
    self.durationObserver = nil
  }
}
