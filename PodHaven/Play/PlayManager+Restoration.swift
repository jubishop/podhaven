// Copyright Justin Bishop, 2026

import Foundation
import Logging

extension PlayManager {
  func restorePersistedEpisodeIfNeeded(preserving requestID: UUID) async {
    guard playbackRequestRevision == requestID else { return }
    guard sharedState.onDeck == nil else { return }
    guard let currentEpisodeID = sharedState.currentEpisodeID else { return }
    guard case .none = mediaServicesRecoveryState else { return }

    Self.log.info("Loading persisted episode \(currentEpisodeID)")
    do {
      let podcastEpisode = try await repo.podcastEpisode(currentEpisodeID)
      guard playbackRequestRevision == requestID,
        sharedState.onDeck == nil,
        sharedState.currentEpisodeID == currentEpisodeID,
        case .none = mediaServicesRecoveryState
      else { return }
      guard let podcastEpisode else {
        Self.log.warning("Persisted episode \(currentEpisodeID) not found in database")
        stateManager.clearOnDeck()
        return
      }
      try await load(podcastEpisode, preserving: requestID)
    } catch {
      Self.log.caughtError(
        "restorePersistedEpisodeIfNeeded: failed to load persisted episode \(currentEpisodeID)",
        error
      )
    }
  }

  private func restorePendingPlaybackRequestIfNeeded(preserving requestID: UUID) async {
    guard playbackRequestRevision == requestID else { return }
    guard case .play(let episodeID) = pendingPlaybackRequest else { return }
    guard sharedState.onDeck?.id != episodeID else { return }

    Self.log.info("Loading episode \(episodeID) for pending playback")
    do {
      let podcastEpisode = try await repo.podcastEpisode(episodeID)
      guard playbackRequestRevision == requestID,
        case .play(let pendingEpisodeID) = pendingPlaybackRequest,
        pendingEpisodeID == episodeID
      else { return }
      guard let podcastEpisode else {
        Self.log.warning("Pending episode \(episodeID) not found in database")
        pendingPlaybackRequest = .none
        if sharedState.onDeck == nil && sharedState.currentEpisodeID == episodeID {
          stateManager.clearOnDeck()
        }
        return
      }
      try await load(podcastEpisode, preserving: requestID)
    } catch {
      Self.log.caughtError(
        "restorePendingPlaybackRequestIfNeeded: failed to load episode \(episodeID)",
        error
      )
    }
  }

  func restorePersistedEpisodeForForeground() async {
    let requestID = playbackRequestRevision
    await restorePendingPlaybackRequestIfNeeded(preserving: requestID)
    guard playbackRequestRevision == requestID else { return }
    if case .play(let episodeID) = pendingPlaybackRequest {
      guard sharedState.onDeck?.id == episodeID else {
        Self.log.info("Pending playback for episode \(episodeID) remains deferred")
        return
      }
      await fulfillPendingPlaybackRequest(preserving: requestID)
      return
    }

    await restorePersistedEpisodeIfNeeded(preserving: requestID)
    await fulfillPendingPlaybackRequest(preserving: requestID)
  }

  func fulfillPendingPlaybackRequest(preserving requestID: UUID) async {
    let player = await podAVPlayer
    guard playbackRequestRevision == requestID else { return }
    guard case .play(let episodeID) = pendingPlaybackRequest else { return }
    guard let onDeck = sharedState.onDeck else {
      if sharedState.currentEpisodeID == episodeID {
        Self.log.info("play: deferring episode \(episodeID) until persisted playback is restored")
      } else {
        pendingPlaybackRequest = .none
        Self.log.warning("play: nothing to play")
      }
      return
    }
    guard onDeck.id == episodeID else {
      pendingPlaybackRequest = .none
      Self.log.warning(
        "play: dropping stale request for episode \(episodeID); on-deck episode is \(onDeck.id)"
      )
      return
    }

    pendingPlaybackRequest = .none
    await player.play(requestID: requestID)
  }
}
