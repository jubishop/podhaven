// Copyright Justin Bishop, 2025

import Factory
import Foundation
import GRDB

@Observable @MainActor final class EpisodeViewModel {
  @ObservationIgnored @LazyInjected(\.alert) private var alert
  @ObservationIgnored @LazyInjected(\.repo) private var repo
  @ObservationIgnored @LazyInjected(\.queue) private var queue
  @ObservationIgnored @LazyInjected(\.playManager) private var playManager
  @ObservationIgnored @LazyInjected(\.playState) private var playState

  private var podcastEpisode: PodcastEpisode
  var podcast: Podcast { podcastEpisode.podcast }
  var episode: Episode { podcastEpisode.episode }

  init(podcastEpisode: PodcastEpisode) {
    self.podcastEpisode = podcastEpisode
  }

  func execute() async {
    do {
      try await observeEpisode()
    } catch {
      alert.andReport(error)
    }
  }

  var onDeck: Bool { playState.isOnDeck(podcastEpisode) }

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

  // MARK: - Private Helpers

  private func observeEpisode() async throws {
    let observer =
      ValueObservation.tracking(
        Episode
          .filter(id: episode.id)
          .including(required: Episode.podcast)
          .asRequest(of: PodcastEpisode.self)
          .fetchOne
      )
      .removeDuplicates()

    for try await podcastEpisode in observer.values(in: repo.db) {
      guard let podcastEpisode = podcastEpisode
      else { throw Err.msg("No return from DB for: \(episode.toString)") }
      self.podcastEpisode = podcastEpisode
    }
  }
}
