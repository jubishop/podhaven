// Copyright Justin Bishop, 2025

import Factory
import Foundation
import GRDB

@Observable @MainActor class TrendingEpisodeViewModel {
  @ObservationIgnored @LazyInjected(\.alert) private var alert
  @ObservationIgnored @LazyInjected(\.playManager) private var playManager
  @ObservationIgnored @LazyInjected(\.playState) private var playState
  @ObservationIgnored @LazyInjected(\.queue) private var queue
  @ObservationIgnored @LazyInjected(\.repo) private var repo

  private let unsavedPodcastEpisode: UnsavedPodcastEpisode
  var unsavedPodcast: UnsavedPodcast { unsavedPodcastEpisode.unsavedPodcast }
  var unsavedEpisode: UnsavedEpisode { unsavedPodcastEpisode.unsavedEpisode }

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
    if let podcastEpisode = self.podcastEpisode { return podcastEpisode }

    let podcastEpisode = try await repo.addEpisode(unsavedPodcastEpisode, fetchIfExists: true)
    self.podcastEpisode = podcastEpisode
    return podcastEpisode
  }

  private func fetchEpisode() async throws {
    guard podcastEpisode == nil
    else { return }

    podcastEpisode = try await repo.episode(unsavedEpisode.media)
  }
}
