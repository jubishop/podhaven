// Copyright Justin Bishop, 2024

import AVFoundation
import Foundation

actor PlayManager : Sendable {
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
//  private var player: AVPlayer?
//  private var playerObserver: Any?
//  private var timeObserver: Any?
//
//  var progress: Double = 0.0
//  var durationText: String = "0:00"
//
//  private var duration: Double {
//    player?.currentItem?.duration.seconds ?? 0
//  }
//
//  fileprivate init() {
//
//  }
//  
//  func load(urlString: String) async {
//    guard let url = URL(string: urlString) else {
//      await Alert.shared("Invalid URL for playback: \(urlString)")
//      return
//    }
//
//    let playerItem = AVPlayerItem(url: url)
//    player = AVPlayer(playerItem: playerItem)
//
//    // Observe duration
//    playerObserver = playerItem.observe(\.duration, options: [.new, .initial]) {
//      [weak self] item, _ in
//      DispatchQueue.main.async {
//        self?.updateDuration()
//      }
//    }
//
//    // Observe progress
//    timeObserver = player?
//      .addPeriodicTimeObserver(
//        forInterval: CMTime(seconds: 1, preferredTimescale: 600),
//        queue: .main
//      ) { [weak self] time in
//        self?.updateProgress()
//      }
//  }
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
