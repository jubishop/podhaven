// Copyright Justin Bishop, 2026

import AppIntents
import FactoryKit
import Logging
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

  private static let log = Log.as("PlayEpisodeIntent")

  func perform() async throws -> some IntentResult {
    #if !WIDGET_EXTENSION
    let appLauncher = Container.shared.appLauncher()
    await appLauncher.prepareForPlayback()

    let repo = Container.shared.repo()
    let playManager = Container.shared.playManager()
    let id = Episode.ID(rawValue: Int64(episodeID))

    let result: PlayManager.SelectionResult
    do {
      guard let podcastEpisode = try await repo.podcastEpisode(id) else {
        Self.log.warning("perform: episode \(id) not found")
        return .result()
      }
      result = try await playManager.play(podcastEpisode)
    } catch {
      Self.log.caughtError("perform: failed for episode \(id)", error)
      throw error
    }

    switch result {
    case .ready:
      break
    case .superseded:
      Self.log.info("perform: playback of episode \(id) was superseded")
    case .unavailable:
      Self.log.notice("perform: episode \(id) is unavailable for playback")
    }
    return .result()
    #else
    Assert.fatal("PlayEpisodeIntent should never execute in widget process")
    #endif
  }
}
