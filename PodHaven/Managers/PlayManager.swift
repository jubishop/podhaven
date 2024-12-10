// Copyright Justin Bishop, 2024

import AVFoundation
import Foundation

actor PlayManager: Sendable {
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
  //
  //  // TODO: Stop playback when the app is terminated...
  //
  private var avPlayer = AVPlayer()
  //  private var playerObserver: Any?
  //  private var timeObserver: Any?

  fileprivate init() {
  }

  func start(_ url: URL) {
    let avPlayerItem = AVPlayerItem(url: url)
    avPlayer.replaceCurrentItem(with: avPlayerItem)

    let playerObserver = avPlayerItem.observe(
      \.duration,
      options: [.initial, .new]
    ) { _, change in
      if let duration = change.newValue {
        print(duration)
      }
    }

    let timeObserver = avPlayer.addPeriodicTimeObserver(
      forInterval: CMTime(seconds: 1, preferredTimescale: 100),
      queue: .global(qos: .utility)
    ) { time in
      print(time)
    }

    avPlayer.play()
  }
  //
  //  func play() {
  //    player?.play()
  //  }
  //
  //  func pause() {
  //    player?.pause()
  //  }
  //
  //  func stop() {
  //    player?.pause()
  //    if let timeObserver = timeObserver {
  //      player?.removeTimeObserver(timeObserver)
  //    }
  //    player = nil
  //  }
  //
  //  func seekForward() {
  //    guard let currentTime = player?.currentTime() else { return }
  //    let newTime = CMTimeGetSeconds(currentTime) + 10
  //    seek(to: newTime)
  //  }
  //
  //  func seekBackward() {
  //    guard let currentTime = player?.currentTime() else { return }
  //    let newTime = max(CMTimeGetSeconds(currentTime) - 10, 0)
  //    seek(to: newTime)
  //  }
  //
  //  private func seek(to seconds: Double) {
  //    let time = CMTime(seconds: seconds, preferredTimescale: 600)
  //    player?.seek(to: time)
  //  }
  //
  //  private func updateProgress() {
  //    guard let currentTime = player?.currentTime().seconds, duration > 0 else {
  //      return
  //    }
  //    progress = currentTime / duration
  //  }
  //
  //  private func updateDuration() {
  //    durationText = formatTime(seconds: duration)
  //  }
  //
  //  private func formatTime(seconds: Double) -> String {
  //    guard !seconds.isNaN else { return "0:00" }
  //    let minutes = Int(seconds) / 60
  //    let seconds = Int(seconds) % 60
  //    return String(format: "%d:%02d", minutes, seconds)
  //  }
}
