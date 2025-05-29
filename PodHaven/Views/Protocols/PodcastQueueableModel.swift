// Copyright Justin Bishop, 2025

import FactoryKit
import Foundation

@MainActor protocol PodcastQueueableModel: AnyObject, EpisodeQueueable, PodcastEpisodeGettable {}

@MainActor extension PodcastQueueableModel {
  private var playManager: PlayManager { Container.shared.playManager() }
  private var queue: Queue { Container.shared.queue() }

  func playEpisode(_ episode: EpisodeType) {
    Task { [weak self] in
      guard let self else { return }
      let podcastEpisode = try await getPodcastEpisode(episode)
      try await playManager.load(podcastEpisode)
      await playManager.play()
    }
  }

  func queueEpisodeOnTop(_ episode: EpisodeType) {
    Task { [weak self] in
      guard let self else { return }
      let episodeID = try await getEpisodeID(episode)
      try await queue.unshift(episodeID)
    }
  }

  func queueEpisodeAtBottom(_ episode: EpisodeType) {
    Task { [weak self] in
      guard let self else { return }
      let episodeID = try await getEpisodeID(episode)
      try await queue.append(episodeID)
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
