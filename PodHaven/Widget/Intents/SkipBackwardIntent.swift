// Copyright Justin Bishop, 2026

import AppIntents

#if !WIDGET_EXTENSION
import FactoryKit
#endif

struct SkipBackwardIntent: AudioPlaybackIntent {
  static let title: LocalizedStringResource = "Skip Backward"
  static let description: IntentDescription = "Skips backward by the configured interval."

  func perform() async throws -> some IntentResult {
    #if !WIDGET_EXTENSION
    let playManager = Container.shared.playManager()
    await playManager.seekBackward()
    #else
    assertionFailure("AudioPlaybackIntent should never execute in widget process")
    #endif
    return .result()
  }
}
