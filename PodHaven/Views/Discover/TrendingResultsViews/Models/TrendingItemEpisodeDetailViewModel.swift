// Copyright Justin Bishop, 2025

import Factory
import Foundation
import GRDB

@Observable @MainActor class TrendingItemEpisodeDetailViewModel {
  @ObservationIgnored @LazyInjected(\.repo) private var repo
  @ObservationIgnored @LazyInjected(\.queue) private var queue
  @ObservationIgnored @LazyInjected(\.playManager) private var playManager
  @ObservationIgnored @LazyInjected(\.playState) private var playState

  let unsavedPodcast: UnsavedPodcast
  let unsavedEpisode: UnsavedEpisode

  private var fetchAttempted = false
  private var podcastEpisode: PodcastEpisode?
  var podcast: Podcast? { podcastEpisode?.podcast }
  var episode: Episode? { podcastEpisode?.episode }

  init(unsavedPodcast: UnsavedPodcast, unsavedEpisode: UnsavedEpisode) {
    self.unsavedPodcast = unsavedPodcast
    self.unsavedEpisode = unsavedEpisode
  }

  var onDeck: Bool {
    guard let podcastEpisode = self.podcastEpisode
    else { return false }

    return playState.isOnDeck(podcastEpisode)
  }

  func playNow() {
    Task {
      try await playManager.load(podcastEpisode)
      await playManager.play()
    }
  }

  func addToTopOfQueue() {
    Task { try await queue.unshift(episode.id) }
  }

  func appendToQueue() {
    Task { try await queue.append(episode.id) }
  }

  func fetchOrCreateEpisode() async throws -> PodcastEpisode {
    try await fetchEpisode()
    if let existingEpisode = self.podcastEpisode {
      return existingEpisode
    }
    // TODO: Check if podcast exists just without this episode
    //   then either add the episode or entire "series"
    return existingEpisode
  }

  func fetchEpisode() async throws {
    guard !fetchAttempted
    else { return }

    fetchAttempted = true
    podcastEpisode = try await repo.episode(unsavedEpisode.media)
  }
}
