// Copyright Justin Bishop, 2026

import Foundation
import Logging

enum OnDeckRecoveryState: Equatable {
  enum Cause {
    case failedRestore
    case mediaServicesReset
  }

  case none
  case awaitingUserAction(Episode.ID, Cause)
}

extension PlayManager {
  var onDeckRecoveryEpisodeID: Episode.ID? {
    guard case .awaitingUserAction(let episodeID, _) = onDeckRecoveryState else { return nil }
    return episodeID
  }

  func onDeckRecoveryEpisode(
    whenLoading podcastEpisode: PodcastEpisode
  ) async throws -> PodcastEpisode? {
    guard let recoveryEpisodeID = onDeckRecoveryEpisodeID else { return nil }
    guard recoveryEpisodeID != podcastEpisode.id else { return podcastEpisode }
    return try await repo.podcastEpisode(recoveryEpisodeID)
  }

  func beginMediaServicesRecovery(interruptedEpisodeID: Episode.ID?) {
    pendingPlaybackRequest = .none
    NowPlayingInfo.clear()
    onDeckBecameCurrentAt = nil

    if let interruptedEpisodeID {
      onDeckRecoveryState = .awaitingUserAction(interruptedEpisodeID, .mediaServicesReset)
    } else {
      onDeckRecoveryState = .none
      stateManager.clearOnDeck()
    }
    setStatus(sharedState.onDeck == nil ? .stopped : .paused)
    Task { @MainActor in CommandCenter.updateNextTrack() }
  }

  func beginFailedRestoreRecovery(_ podcastEpisode: PodcastEpisode) async {
    onDeckRecoveryState = .awaitingUserAction(podcastEpisode.id, .failedRestore)
    await restoreOnDeckRecoveryPresentation(podcastEpisode)
  }

  func restoreOnDeckRecoveryPresentation(_ podcastEpisode: PodcastEpisode) async {
    guard onDeckRecoveryEpisodeID == podcastEpisode.id else { return }
    stateManager.setOnDeck(podcastEpisode)
    fetchImage(for: podcastEpisode)
    onDeckBecameCurrentAt = nil
    setStatus(.paused)
    Task { @MainActor in CommandCenter.updateNextTrack() }

    do {
      try await queue.dequeue(podcastEpisode.id)
    } catch {
      Self.log.caughtError(
        "restoreOnDeckRecoveryPresentation: failed to dequeue episode \(podcastEpisode.id)",
        error
      )
    }
  }

  func completeOnDeckRecovery() {
    onDeckRecoveryState = .none
  }

  func reloadOnDeckRecoveryIfNeeded(for episodeID: Episode.ID, preserving requestID: UUID)
    async -> Bool
  {
    guard playbackRequestRevision == requestID else { return false }
    guard onDeckRecoveryEpisodeID == episodeID else { return true }

    do {
      let podcastEpisode = try await repo.podcastEpisode(episodeID)
      guard playbackRequestRevision == requestID else { return false }
      guard let podcastEpisode else {
        Self.log.warning("On-deck recovery episode \(episodeID) not found in database")
        onDeckRecoveryState = .none
        pendingPlaybackRequest = .none
        stateManager.clearOnDeck()
        setStatus(.stopped)
        return false
      }
      let loaded = try await load(podcastEpisode, preserving: requestID)
      guard playbackRequestRevision == requestID else { return false }
      guard loaded else {
        pendingPlaybackRequest = .none
        return false
      }
      return true
    } catch {
      Self.log.caughtError(
        "play: failed to reload on-deck recovery episode \(episodeID)",
        error
      )
      guard playbackRequestRevision == requestID else { return false }
      pendingPlaybackRequest = .none
      await alert(ErrorKit.message(for: error))
      return false
    }
  }

  func clearOnDeckRecoveryIfDeleted(_ episodeIDs: Set<Episode.ID>) {
    guard let episodeID = onDeckRecoveryEpisodeID, episodeIDs.contains(episodeID) else {
      return
    }
    onDeckRecoveryState = .none
  }

  func clearOnDeckRecovery(for episodeID: Episode.ID) {
    guard onDeckRecoveryEpisodeID == episodeID else { return }
    onDeckRecoveryState = .none
  }

  func clearOnDeckRecovery() {
    onDeckRecoveryState = .none
  }
}
