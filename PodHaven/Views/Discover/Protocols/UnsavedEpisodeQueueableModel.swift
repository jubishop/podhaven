// Copyright Justin Bishop, 2025

import Factory
import Foundation
import GRDB

@MainActor protocol UnsavedEpisodeQueueableModel: AnyObject, Observable {
  var unsavedPodcastEpisode: UnsavedPodcastEpisode { get }
  var podcastEpisode: PodcastEpisode? { get set }

  var unsavedPodcast: UnsavedPodcast { get }
  var unsavedEpisode: UnsavedEpisode { get }
  var onDeck: Bool { get }

  func playNow()
  func addToTopOfQueue()
  func appendToQueue()
}

@MainActor extension UnsavedEpisodeQueueableModel {
  var unsavedPodcast: UnsavedPodcast { unsavedPodcastEpisode.unsavedPodcast }
  var unsavedEpisode: UnsavedEpisode { unsavedPodcastEpisode.unsavedEpisode }

  var onDeck: Bool {
    guard let podcastEpisode = self.podcastEpisode
    else { return false }

    return Container.shared.playState().isOnDeck(podcastEpisode)
  }

  func playNow() {
    Task {
      let podcastEpisode = try await self.fetchOrCreateEpisode()
      try await Container.shared.playManager().load(podcastEpisode)
      await Container.shared.playManager().play()
    }
  }

  func addToTopOfQueue() {
    Task {
      let podcastEpisode = try await self.fetchOrCreateEpisode()
      try await Container.shared.queue().unshift(podcastEpisode.episode.id)
    }
  }

  func appendToQueue() {
    Task {
      let podcastEpisode = try await self.fetchOrCreateEpisode()
      try await Container.shared.queue().append(podcastEpisode.episode.id)
    }
  }

  // MARK: - Private Helpers

  private func fetchOrCreateEpisode() async throws -> PodcastEpisode {
    if let podcastEpisode = self.podcastEpisode { return podcastEpisode }

    let podcastEpisode = try await Container.shared.repo()
      .upsertPodcastEpisode(unsavedPodcastEpisode)
    self.podcastEpisode = podcastEpisode
    return podcastEpisode
  }
}
