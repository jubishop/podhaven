// Copyright Justin Bishop, 2026

import AppIntents
import FactoryKit

struct SkipBackwardIntent: AudioPlaybackIntent {
  static let title: LocalizedStringResource = "Skip Backward"
  static let description: IntentDescription = "Skips backward by the configured interval."

  func perform() async throws -> some IntentResult {
    #if !WIDGET_EXTENSION
    let appLauncher = Container.shared.appLauncher()
    await appLauncher.prepareForPlayback()

    let playManager = Container.shared.playManager()
    await playManager.seekBackward()

    return .result()
    #else
    Assert.fatal("SkipBackwardIntent should never execute in widget process")
    #endif
  }
}
