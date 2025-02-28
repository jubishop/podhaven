// Copyright Justin Bishop, 2025

import Factory
import Foundation
import GRDB

@Observable @MainActor class TrendingEpisodeViewModel {
  @ObservationIgnored @LazyInjected(\.alert) private var alert
  @ObservationIgnored @LazyInjected(\.repo) private var repo
  @ObservationIgnored @LazyInjected(\.queue) private var queue
  @ObservationIgnored @LazyInjected(\.playManager) private var playManager
  @ObservationIgnored @LazyInjected(\.playState) private var playState

  private let unsavedPodcastEpisode: UnsavedPodcastEpisode
  var unsavedPodcast: UnsavedPodcast { unsavedPodcastEpisode.unsavedPodcast }
  var unsavedEpisode: UnsavedEpisode { unsavedPodcastEpisode.unsavedEpisode }

  private var fetchAttempted = false
  private var podcastEpisode: PodcastEpisode?

  init(unsavedPodcastEpisode: UnsavedPodcastEpisode) {
    self.unsavedPodcastEpisode = unsavedPodcastEpisode
  }

  func execute() async {
    do {
      try await fetchEpisode()
    } catch {
      alert.andReport(error)
    }
  }

  var onDeck: Bool {
    guard let podcastEpisode = self.podcastEpisode
    else { return false }

    return playState.isOnDeck(podcastEpisode)
  }

  func playNow() {
    Task {
      let podcastEpisode = try await self.fetchOrCreateEpisode()
      try await playManager.load(podcastEpisode)
      await playManager.play()
    }
  }

  func addToTopOfQueue() {
    Task {
      let podcastEpisode = try await self.fetchOrCreateEpisode()
      try await queue.unshift(podcastEpisode.episode.id)
    }
  }

  func appendToQueue() {
    Task {
      let podcastEpisode = try await self.fetchOrCreateEpisode()
      try await queue.append(podcastEpisode.episode.id)
    }
  }

  // MARK: - Private Helpers

  private func fetchOrCreateEpisode() async throws -> PodcastEpisode {
    try await fetchEpisode()
    if let existingEpisode = self.podcastEpisode {
      return existingEpisode
    }

    let podcastEpisode = try await repo.addEpisode(unsavedPodcastEpisode)
    self.podcastEpisode = podcastEpisode
    return podcastEpisode
  }

  private func fetchEpisode() async throws {
    guard !fetchAttempted
    else { return }

    fetchAttempted = true
    podcastEpisode = try await repo.episode(unsavedEpisode.media)
  }
}
