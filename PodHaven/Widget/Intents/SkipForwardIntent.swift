// Copyright Justin Bishop, 2026

import AppIntents

#if !WIDGET_EXTENSION
import FactoryKit
#endif

struct SkipForwardIntent: AudioPlaybackIntent {
  static let title: LocalizedStringResource = "Skip Forward"
  static let description: IntentDescription = "Skips forward by the configured interval."

  func perform() async throws -> some IntentResult {
    #if !WIDGET_EXTENSION
    let playManager = Container.shared.playManager()
    await playManager.seekForward()
    #else
    assertionFailure("AudioPlaybackIntent should never execute in widget process")
    #endif
    return .result()
  }
}
