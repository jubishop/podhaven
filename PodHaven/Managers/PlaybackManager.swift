// Copyright Justin Bishop, 2024

import AVFoundation
import Foundation

struct PlaybackManager: Sendable {
  static let shared = { PlaybackManager() }()

  func configureAudioSession() async {
    do {
      try AVAudioSession.sharedInstance()
        .setCategory(
          .playback,
          mode: .spokenAudio,
          policy: .longFormAudio
        )
    } catch {
      await MainActor.run {
        Alert.shared("Failed to set the audio session configuration")
      }
    }
  }
}
