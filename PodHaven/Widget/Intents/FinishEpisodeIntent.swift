// Copyright Justin Bishop, 2026

import AppIntents
import FactoryKit

struct FinishEpisodeIntent: AudioPlaybackIntent {
  static let title: LocalizedStringResource = "Finish Episode"
  static let description: IntentDescription = "Finishes the current episode."

  func perform() async throws -> some IntentResult {
    #if !WIDGET_EXTENSION
    let appLauncher = Container.shared.appLauncher()
    await appLauncher.prepareForPlayback()

    let playManager = Container.shared.playManager()
    await playManager.finishEpisode()

    return .result()
    #else
    Assert.fatal("FinishEpisodeIntent should never execute in widget process")
    #endif
  }
}
