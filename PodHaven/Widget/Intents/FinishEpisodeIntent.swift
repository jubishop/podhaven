// Copyright Justin Bishop, 2026

import AppIntents
import FactoryKit

struct FinishEpisodeIntent: AudioPlaybackIntent {
  static let title: LocalizedStringResource = "Finish Episode"
  static let description: IntentDescription = "Finishes the current episode and plays the next one."

  func perform() async throws -> some IntentResult {
    #if !WIDGET_EXTENSION
    let playManager = Container.shared.playManager()
    await playManager.finishEpisode()
    return .result()
    #else
    Assert.fatal("FinishEpisodeIntent should never execute in widget process")
    #endif
  }
}
