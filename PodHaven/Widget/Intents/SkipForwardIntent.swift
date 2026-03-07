// Copyright Justin Bishop, 2026

import AppIntents
import FactoryKit

struct SkipForwardIntent: AudioPlaybackIntent {
  static let title: LocalizedStringResource = "Skip Forward"
  static let description: IntentDescription = "Skips forward by the configured interval."

  func perform() async throws -> some IntentResult {
    #if !WIDGET_EXTENSION
    let appLauncher = Container.shared.appLauncher()
    await appLauncher.prepareForPlayback()

    let playManager = Container.shared.playManager()
    await playManager.seekForward()
    return .result()
    #else
    Assert.fatal("SkipForwardIntent should never execute in widget process")
    #endif
  }
}
