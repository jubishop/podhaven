// Copyright Justin Bishop, 2026

import AppIntents
import FactoryKit

struct PlayPauseIntent: AudioPlaybackIntent {
  static let title: LocalizedStringResource = "Play or Pause"
  static let description: IntentDescription = "Toggles playback of the current episode."

  func perform() async throws -> some IntentResult {
    #if !WIDGET_EXTENSION
    let playManager = Container.shared.playManager()
    await playManager.toggle()
    return .result()
    #else
    Assert.fatal("AudioPlaybackIntent should never execute in widget process")
    #endif
  }
}
