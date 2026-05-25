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
  @DynamicInjected(\.sleeper) private var sleeper

  private static let log = Log.as(LogSubsystem.State.manager)

  private let startOnce = Once()
  private let onDeckObservationTask = ThreadSafe<Task<Void, Never>?>(nil)

  // MARK: - Initialization

  fileprivate init() {}

  func start() {
    startOnce.run {
      Self.log.debug("start: executing")

      startObservingQueuedPodcastEpisodes()
      startObservingTags()
    }
  }

  // MARK: - On Deck

  func setOnDeck(_ podcastEpisode: PodcastEpisode) {
    guard sharedState.onDeck?.id != podcastEpisode.id else { return }

    onDeckObservationTask()?.cancel()

    // Set onDeck and currentEpisodeID immediately so callers can rely on them being set
    sharedState.currentEpisodeID = podcastEpisode.id
    sharedState.$onDeck.new(OnDeck(from: podcastEpisode))

    // Observe for updates (e.g., if episode is marked finished, cached, etc.)
    onDeckObservationTask(
      Task {
        var retryDelay: Duration = .seconds(1)
        while !Task.isCancelled {
          do {
            for try await observed in observatory.onDeck(podcastEpisode.id) {
              guard !Task.isCancelled else { return }
              retryDelay = .seconds(1)

              if var observed {
                // Observatory emits OnDeck with artwork = nil,
                // currentTime = .zero, and maxPlaybackTime = .zero;
                // restore them from current state.
                //
                // The id guard keeps an in-flight emission from resurrecting a
                // slot that clearOnDeck (or a switch to another episode)
                // already changed: cancellation races the emission, so this
                // task can still run after the slot moved on.
                sharedState.$onDeck.update { onDeck in
                  guard onDeck?.id == podcastEpisode.id else { return }
                  observed.artwork = onDeck?.artwork
                  observed.currentTime = onDeck?.currentTime ?? .zero
                  observed.maxPlaybackTime = onDeck?.maxPlaybackTime ?? .zero
                  onDeck = observed
                }
              } else {
                sharedState.$onDeck.update { onDeck in
                  guard onDeck?.id == podcastEpisode.id else { return }
                  onDeck = nil
                }
              }
            }
          } catch {
            Self.log.caughtError(
              "setOnDeck: observation failed for episode \(podcastEpisode.id)",
              error
            )
            try? await sleeper.sleep(for: retryDelay)
            retryDelay = min(retryDelay * 2, .seconds(60))
          }
        }
      }
    )
  }

  func clearOnDeck() {
    onDeckObservationTask()?.cancel()
    sharedState.currentEpisodeID = nil
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
    sharedState.$onDeck.update { onDeck in
      onDeck?.currentTime = currentTime
      // Keep the in-memory peak in lockstep with playback so the UI has a
      // live reading; DB catch-up happens via repo.updateCurrentTime's MAX.
      if let current = onDeck?.maxPlaybackTime, currentTime.seconds > current.seconds {
        onDeck?.maxPlaybackTime = currentTime
      }
    }
  }

  // MARK: - Observations

  private func startObservingTags() {
    Task {
      var retryDelay: Duration = .seconds(1)
      while !Task.isCancelled {
        do {
          for try await tags in observatory.tags() {
            guard !Task.isCancelled else { return }
            retryDelay = .seconds(1)
            Self.log.debug("Updating observed tags: \(tags.count) tags")
            sharedState.setTags(tags)
          }
        } catch {
          Self.log.caughtError("startObservingTags: observation failed", error)
          try? await sleeper.sleep(for: retryDelay)
          retryDelay = min(retryDelay * 2, .seconds(60))
        }
      }
    }
  }

  private func startObservingQueuedPodcastEpisodes() {
    Task {
      var retryDelay: Duration = .seconds(1)
      while !Task.isCancelled {
        do {
          for try await queuedPodcastEpisodes in observatory.queuedPodcastEpisodes() {
            guard !Task.isCancelled else { return }
            retryDelay = .seconds(1)
            Self.log.debug("Updating observed queue: \(queuedPodcastEpisodes.count) episodes")
            sharedState.setQueuedPodcastEpisodes(queuedPodcastEpisodes)
          }
        } catch {
          Self.log.caughtError("startObservingQueuedPodcastEpisodes: observation failed", error)
          try? await sleeper.sleep(for: retryDelay)
          retryDelay = min(retryDelay * 2, .seconds(60))
        }
      }
    }
  }
}
