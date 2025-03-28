// Copyright Justin Bishop, 2025

import Factory
import Foundation

@MainActor protocol UnsavedPodcastQueueableModel: EpisodeQueueable, EpisodeUpserter {}

@MainActor extension UnsavedPodcastQueueableModel {
  func playEpisode(_ episode: EpisodeType) {
    Task {
      let podcastEpisode = try await upsert(episode)
      try await Container.shared.playManager().load(podcastEpisode)
      await Container.shared.playManager().play()
    }
  }

  func queueEpisodeOnTop(_ episode: EpisodeType) {
    Task {
      let podcastEpisode = try await upsert(episode)
      try await Container.shared.queue().unshift(podcastEpisode.id)
    }
  }

  func queueEpisodeAtBottom(_ episode: EpisodeType) {
    Task {
      let podcastEpisode = try await upsert(episode)
      try await Container.shared.queue().append(podcastEpisode.id)
    }
  }
}
