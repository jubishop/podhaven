// Copyright Justin Bishop, 2026

import AppIntents

#if !WIDGET_EXTENSION
import FactoryKit
#endif

struct PlayPauseIntent: AudioPlaybackIntent {
  static let title: LocalizedStringResource = "Play or Pause"
  static let description: IntentDescription = "Toggles playback of the current episode."

  func perform() async throws -> some IntentResult {
    #if !WIDGET_EXTENSION
    let playManager = Container.shared.playManager()
    let sharedState = Container.shared.sharedState()
    if sharedState.playbackStatus.playing {
      await playManager.pause()
    } else {
      await playManager.play()
    }
    #else
    Assert.fatal("AudioPlaybackIntent should never execute in widget process")
    #endif
    return .result()
  }
}
