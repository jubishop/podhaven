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

  private static let log = Log.as(LogSubsystem.EpisodesView.detail)

  // MARK: - State Management

  var onDeck: Bool {
    guard let podcastEpisode = self.podcastEpisode,
      let onDeck = playState.onDeck
    else { return false }

    return onDeck == podcastEpisode
  }

  let searchedText: String

  private var podcastEpisode: PodcastEpisode?
  let unsavedPodcastEpisode: UnsavedPodcastEpisode
  private var maxQueuePosition: Int? = nil

  // MARK: - Initialization

  init(searchedPodcastEpisode: SearchedPodcastEpisode) {
    self.searchedText = searchedPodcastEpisode.searchedText
    self.unsavedPodcastEpisode = searchedPodcastEpisode.unsavedPodcastEpisode
  }

  func execute() async {
    // Observe max queue position
    Task { [weak self] in
      guard let self else { return }
      do {
        for try await maxPosition in observatory.maxQueuePosition() {
          self.maxQueuePosition = maxPosition
        }
      } catch {
        Self.log.error(error)
        alert(ErrorKit.message(for: error))
      }
    }
    
    // Observe this episode record updates
    Task { [weak self] in
      guard let self else { return }
      do {
        for try await podcastEpisode in observatory.podcastEpisode(unsavedPodcastEpisode.unsavedEpisode.media) {
          if self.podcastEpisode == podcastEpisode { continue }
          self.podcastEpisode = podcastEpisode
        }
      } catch {
        alert("Couldn't observe podcast episode: \(unsavedPodcastEpisode.toString)")
      }
    }
  }

  // MARK: - Public Functions

  func playNow() {
    Task { [weak self] in
      guard let self else { return }
      let podcastEpisode: PodcastEpisode
      do {
        podcastEpisode = try await fetchOrCreateEpisode()
      } catch {
        Self.log.error(error)
        alert("Failed to fetch or create episode: \(unsavedPodcastEpisode.unsavedEpisode.title)")
        return
      }

      do {
        try await playManager.load(podcastEpisode)
        await playManager.play()
      } catch {
        alert("Failed to load episode: \(podcastEpisode.episode.title)")
        Self.log.error(error)
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

  // MARK: - Queue Position State

  var atTopOfQueue: Bool {
    guard let podcastEpisode = self.podcastEpisode else { return false }
    return podcastEpisode.episode.queueOrder == 0
  }

  var atBottomOfQueue: Bool {
    guard let podcastEpisode = self.podcastEpisode,
          let queueOrder = podcastEpisode.episode.queueOrder
    else { return false }

    return queueOrder == maxQueuePosition
  }

  // MARK: - Private Helpers

  private func fetchOrCreateEpisode() async throws -> PodcastEpisode {
    if let podcastEpisode = self.podcastEpisode { return podcastEpisode }

    let podcastEpisode = try await repo.upsertPodcastEpisode(unsavedPodcastEpisode)
    self.podcastEpisode = podcastEpisode
    return podcastEpisode
  }
}
