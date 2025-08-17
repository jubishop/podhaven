// Copyright Justin Bishop, 2025

import FactoryKit
import Foundation
import GRDB
import Logging

@Observable @MainActor class EpisodeDetailViewModel {
  @ObservationIgnored @DynamicInjected(\.alert) private var alert
  @ObservationIgnored @DynamicInjected(\.observatory) private var observatory
  @ObservationIgnored @DynamicInjected(\.playManager) private var playManager
  @ObservationIgnored @DynamicInjected(\.playState) private var playState
  @ObservationIgnored @DynamicInjected(\.queue) private var queue
  @ObservationIgnored @DynamicInjected(\.repo) private var repo

  private static let log = Log.as(LogSubsystem.EpisodesView.detail)

  // MARK: - State Management

  var onDeck: Bool {
    guard let onDeck = playState.onDeck else { return false }
    return onDeck == podcastEpisode
  }

  private var maxQueuePosition: Int? = nil
  var podcastEpisode: PodcastEpisode

  // MARK: - Initialization

  init(podcastEpisode: PodcastEpisode) {
    self.podcastEpisode = podcastEpisode
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
        for try await podcastEpisode in observatory.podcastEpisode(self.podcastEpisode.id) {
          guard let podcastEpisode = podcastEpisode
          else {
            throw ObservatoryError.recordNotFound(
              type: PodcastEpisode.self,
              id: self.podcastEpisode.episode.id.rawValue
            )
          }

          self.podcastEpisode = podcastEpisode
        }
      } catch {
        Self.log.error(error)
        alert(ErrorKit.message(for: error))
      }
    }
  }

  // MARK: - Public Functions

  func playNow() {
    Task { [weak self] in
      guard let self else { return }
      do {
        try await playManager.load(podcastEpisode)
        await playManager.play()
      } catch {
        alert("Failed to load next episode: \(podcastEpisode.episode.title)")
        Self.log.error(error)
      }
    }
  }

  func addToTopOfQueue() {
    Task { [weak self] in
      guard let self else { return }
      try await queue.unshift(podcastEpisode.episode.id)
    }
  }

  func appendToQueue() {
    Task { [weak self] in
      guard let self else { return }
      try await queue.append(podcastEpisode.episode.id)
    }
  }

  // MARK: - Queue Position State

  var atTopOfQueue: Bool {
    podcastEpisode.episode.queueOrder == 0
  }

  var atBottomOfQueue: Bool {
    guard let queueOrder = podcastEpisode.episode.queueOrder
    else { return false }

    return queueOrder == maxQueuePosition
  }
}
