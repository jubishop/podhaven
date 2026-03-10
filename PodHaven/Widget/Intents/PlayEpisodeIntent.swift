// Copyright Justin Bishop, 2026

import AppIntents
import FactoryKit
import Tagged

struct PlayEpisodeIntent: AudioPlaybackIntent {
  static let title: LocalizedStringResource = "Play Episode"
  static let description: IntentDescription = "Plays a specific episode from the queue."

  @Parameter(title: "Episode ID")
  var episodeID: Int

  init() {}

  init(episodeID: Int64) {
    self.episodeID = Int(episodeID)
  }

  func perform() async throws -> some IntentResult {
    #if !WIDGET_EXTENSION
    let appLauncher = Container.shared.appLauncher()
    await appLauncher.prepareForPlayback()

    let repo = Container.shared.repo()
    let playManager = Container.shared.playManager()
    let id = Episode.ID(rawValue: Int64(episodeID))

    if let podcastEpisode = try await repo.podcastEpisode(id) {
      try await playManager.load(podcastEpisode)
      await playManager.play()
    }

    return .result()
    #else
    Assert.fatal("PlayEpisodeIntent should never execute in widget process")
    #endif
  }
}
