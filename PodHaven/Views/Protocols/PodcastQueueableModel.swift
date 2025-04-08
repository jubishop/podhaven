// Copyright Justin Bishop, 2025

import Factory
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
