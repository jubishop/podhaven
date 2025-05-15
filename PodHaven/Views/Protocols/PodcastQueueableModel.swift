// Copyright Justin Bishop, 2025

import FactoryKit
import Foundation

@MainActor protocol PodcastQueueableModel: EpisodeQueueable, PodcastEpisodeGettable {}

@MainActor extension PodcastQueueableModel {
  func playEpisode(_ episode: EpisodeType) {
    Task {
      let podcastEpisode = try await getPodcastEpisode(episode)
      try await Container.shared.playManager().load(podcastEpisode)
      await Container.shared.playManager().play()
    }
  }

  func queueEpisodeOnTop(_ episode: EpisodeType) {
    Task {
      let episodeID = try await getEpisodeID(episode)
      try await Container.shared.queue().unshift(episodeID)
    }
  }

  func queueEpisodeAtBottom(_ episode: EpisodeType) {
    Task {
      let episodeID = try await getEpisodeID(episode)
      try await Container.shared.queue().append(episodeID)
    }
  }
}

@MainActor extension PodcastQueueableModel where EpisodeType == PodcastEpisode {
  func getPodcastEpisode(_ episode: PodcastEpisode) async throws -> PodcastEpisode { episode }
  func getEpisodeID(_ episode: PodcastEpisode) async throws -> Episode.ID { episode.id }
}

@MainActor extension PodcastQueueableModel where EpisodeType == Episode {
  func getEpisodeID(_ episode: Episode) async throws -> Episode.ID { episode.id }
}
