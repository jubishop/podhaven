// Copyright Justin Bishop, 2025

import AVFoundation
import FactoryKit
import Foundation
import GRDB
import Logging
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
    startObservingTags()
  }

  // MARK: - On Deck

  func setOnDeck(_ podcastEpisode: PodcastEpisode) {
    guard sharedState.onDeck?.id != podcastEpisode.id else { return }

    onDeckObservationTask()?.cancel()

    // Set onDeck and currentEpisodeID immediately so callers can rely on them being set
    sharedState.currentEpisodeID = podcastEpisode.id
    sharedState.$onDeck.new(OnDeck(podcastEpisode: podcastEpisode))

    // Observe for updates (e.g., if episode is marked finished, cached, etc.)
    onDeckObservationTask(
      Task {
        do {
          for try await episode in observatory.podcastEpisode(podcastEpisode.id) {
            guard !Task.isCancelled else { return }

            if let episode {
              sharedState.$onDeck.update { onDeck in
                onDeck = OnDeck(
                  podcastEpisode: episode,
                  artwork: onDeck?.artwork,
                  currentTime: onDeck?.currentTime
                )
              }
            } else {
              sharedState.$onDeck.new(nil)
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
    sharedState.$onDeck.new(nil)
  }

  // MARK: - Artwork

  func setArtwork(_ artwork: UIImage, for episodeID: Episode.ID) {
    sharedState.$onDeck.update { onDeck in
      guard onDeck?.id == episodeID else { return }
      onDeck?.artwork = artwork
    }
  }

  // MARK: - Current Time

  func setCurrentTime(_ currentTime: CMTime) {
    sharedState.$onDeck.update { $0?.currentTime = currentTime }
  }

  // MARK: - Observations

  private func startObservingTags() {
    Assert.neverCalled()

    Task {
      do {
        for try await tags in observatory.tags() {
          guard !Task.isCancelled else { return }
          Self.log.debug("Updating observed tags: \(tags.count) tags")
          sharedState.setTags(tags)
        }
      } catch {
        Self.log.error(error)
      }
    }
  }

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
