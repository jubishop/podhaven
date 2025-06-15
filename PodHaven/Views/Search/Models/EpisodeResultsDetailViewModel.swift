// Copyright Justin Bishop, 2025

import FactoryKit
import Foundation
import GRDB
import Logging

@Observable @MainActor class EpisodeResultsDetailViewModel {
  @ObservationIgnored @DynamicInjected(\.alert) private var alert
  @ObservationIgnored @DynamicInjected(\.observatory) private var observatory
  @ObservationIgnored @DynamicInjected(\.playManager) private var playManager
  @ObservationIgnored @DynamicInjected(\.playState) private var playState
  @ObservationIgnored @DynamicInjected(\.queue) private var queue
  @ObservationIgnored @DynamicInjected(\.repo) private var repo

  private let log = Log.as(LogSubsystem.SearchView.episodeDetail)

  // MARK: - State Management

  let searchedText: String
  var unsavedPodcast: UnsavedPodcast { unsavedPodcastEpisode.unsavedPodcast }
  var unsavedEpisode: UnsavedEpisode { unsavedPodcastEpisode.unsavedEpisode }

  var onDeck: Bool {
    guard let podcastEpisode = self.podcastEpisode,
      let onDeck = playState.onDeck
    else { return false }

    return onDeck == podcastEpisode
  }

  private var podcastEpisode: PodcastEpisode?
  private let unsavedPodcastEpisode: UnsavedPodcastEpisode

  // MARK: - Initialization

  init(searchedPodcastEpisode: SearchedPodcastEpisode) {
    self.searchedText = searchedPodcastEpisode.searchedText
    self.unsavedPodcastEpisode = searchedPodcastEpisode.unsavedPodcastEpisode
  }

  func execute() async {
    do {
      for try await podcastEpisode in observatory.podcastEpisode(unsavedEpisode.media) {
        if self.podcastEpisode == podcastEpisode { continue }
        self.podcastEpisode = podcastEpisode
      }
    } catch {
      alert("Couldn't observe podcast episode: \(unsavedPodcastEpisode.toString)")
    }
  }

  // MARK: - Public Functions

  func playNow() {
    Task { [weak self] in
      guard let self else { return }
      do {
        let podcastEpisode = try await fetchOrCreateEpisode()
        try await playManager.load(podcastEpisode)
        await playManager.play()
      } catch {
        log.error(error)
      }
    }
  }

  func addToTopOfQueue() {
    Task { [weak self] in
      guard let self else { return }
      let podcastEpisode = try await fetchOrCreateEpisode()
      try await queue.unshift(podcastEpisode.episode.id)
    }
  }

  func appendToQueue() {
    Task { [weak self] in
      guard let self else { return }
      let podcastEpisode = try await fetchOrCreateEpisode()
      try await queue.append(podcastEpisode.episode.id)
    }
  }

  // MARK: - Private Helpers

  private func fetchOrCreateEpisode() async throws -> PodcastEpisode {
    if let podcastEpisode = self.podcastEpisode { return podcastEpisode }

    let podcastEpisode = try await repo.upsertPodcastEpisode(unsavedPodcastEpisode)
    self.podcastEpisode = podcastEpisode
    return podcastEpisode
  }
}
