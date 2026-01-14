// Copyright Justin Bishop, 2025

import AVFoundation
import FactoryKit
import Foundation
import GRDB
import Logging
import Sharing
import UIKit

extension Container {
  var stateManager: Factory<StateManager> {
    Factory(self) { StateManager() }.scope(.cached)
  }
}

struct StateManager: Sendable {
  @DynamicInjected(\.observatory) private var observatory
  @DynamicInjected(\.sharedState) private var sharedState

  private static let log = Log.as(LogSubsystem.State.manager)

  private let onDeckObservationTask = ThreadSafe<Task<Void, Never>?>(nil)

  // MARK: - Initialization

  fileprivate init() {}

  func start() {
    guard Function.neverCalled() else { return }

    startObservingQueuedPodcastEpisodes()
  }

  // MARK: - On Deck

  func setOnDeck(_ podcastEpisode: PodcastEpisode) {
    guard sharedState.onDeck?.id != podcastEpisode.id else { return }

    onDeckObservationTask()?.cancel()

    // Set onDeck immediately so callers can rely on it being set
    sharedState.$onDeck.withLock { $0 = OnDeck(podcastEpisode: podcastEpisode) }

    // Observe for updates (e.g., if episode is marked finished, cached, etc.)
    onDeckObservationTask(
      Task {
        do {
          for try await episode in observatory.podcastEpisode(podcastEpisode.id) {
            guard !Task.isCancelled else { return }

            if let episode {
              sharedState.$onDeck.withLock { onDeck in
                onDeck = OnDeck(
                  podcastEpisode: episode,
                  artwork: onDeck?.artwork,
                  currentTime: onDeck?.currentTime
                )
              }
            } else {
              sharedState.$onDeck.withLock { $0 = nil }
            }
          }
        } catch {
          Self.log.error(error)
        }
      }
    )
  }

  func clearOnDeck() {
    onDeckObservationTask()?.cancel()
    sharedState.$onDeck.withLock { $0 = nil }
  }

  // MARK: - Artwork

  func setArtwork(_ artwork: UIImage, for episodeID: Episode.ID) {
    sharedState.$onDeck.withLock { onDeck in
      guard onDeck?.id == episodeID else { return }
      onDeck?.artwork = artwork
    }
  }

  // MARK: - Current Time

  func setCurrentTime(_ currentTime: CMTime) {
    sharedState.$onDeck.withLock { $0?.currentTime = currentTime }
  }

  // MARK: - Observations

  private func startObservingQueuedPodcastEpisodes() {
    Assert.neverCalled()

    Task {
      do {
        for try await queuedPodcastEpisodes in observatory.queuedPodcastEpisodes() {
          guard !Task.isCancelled else { return }
          Self.log.debug("Updating observed queue: \(queuedPodcastEpisodes.count) episodes")
          sharedState.setQueuedPodcastEpisodes(queuedPodcastEpisodes)
        }
      } catch {
        Self.log.error(error)
      }
    }
  }
}
