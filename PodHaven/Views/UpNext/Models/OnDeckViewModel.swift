// Copyright Justin Bishop, 2026

import FactoryKit
import Foundation

@MainActor final class OnDeckViewModel: ManagingEpisodes {
  @DynamicInjected(\.repo) private var repo

  func getOrCreatePodcastEpisode(_ episode: OnDeck) async throws -> PodcastEpisode {
    guard let podcastEpisode = try await repo.podcastEpisode(episode.id) else {
      Assert.fatal("PodcastEpisode not found for OnDeck ID \(episode.id)")
    }
    return podcastEpisode
  }
}
