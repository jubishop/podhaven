// Copyright Justin Bishop, 2026

import Foundation
import Logging

enum MediaServicesRecoveryState: Equatable {
  case none
  case awaitingUserAction(Episode.ID)
}

extension PlayManager {
  var mediaServicesRecoveryEpisodeID: Episode.ID? {
    guard case .awaitingUserAction(let episodeID) = mediaServicesRecoveryState else { return nil }
    return episodeID
  }

  func mediaServicesRecoveryEpisode(
    whenLoading podcastEpisode: PodcastEpisode
  ) async throws -> PodcastEpisode? {
    guard let recoveryEpisodeID = mediaServicesRecoveryEpisodeID else { return nil }
    guard recoveryEpisodeID != podcastEpisode.id else { return podcastEpisode }
    return try await repo.podcastEpisode(recoveryEpisodeID)
  }

  func beginMediaServicesRecovery(interruptedEpisodeID: Episode.ID?) {
    pendingPlaybackRequest = .none
    NowPlayingInfo.clear()
    onDeckBecameCurrentAt = nil
    setStatus(.stopped)

    if let interruptedEpisodeID {
      mediaServicesRecoveryState = .awaitingUserAction(interruptedEpisodeID)
    } else {
      mediaServicesRecoveryState = .none
      stateManager.clearOnDeck()
    }
    CommandCenter.updateNextTrack()
  }

  func restoreMediaServicesRecoveryPresentation(_ podcastEpisode: PodcastEpisode) {
    guard mediaServicesRecoveryEpisodeID == podcastEpisode.id else { return }
    stateManager.setOnDeck(podcastEpisode)
    onDeckBecameCurrentAt = nil
    setStatus(.stopped)
    CommandCenter.updateNextTrack()
  }

  func completeMediaServicesRecovery() {
    mediaServicesRecoveryState = .none
  }

  func reloadMediaServicesRecoveryIfNeeded(for episodeID: Episode.ID, preserving requestID: UUID)
    async -> Bool
  {
    guard playbackRequestRevision == requestID else { return false }
    guard mediaServicesRecoveryEpisodeID == episodeID else { return true }

    do {
      let podcastEpisode = try await repo.podcastEpisode(episodeID)
      guard playbackRequestRevision == requestID else { return false }
      guard let podcastEpisode else {
        Self.log.warning("Media-services recovery episode \(episodeID) not found in database")
        mediaServicesRecoveryState = .none
        pendingPlaybackRequest = .none
        stateManager.clearOnDeck()
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
        "play: failed to restore episode \(episodeID) after media-services reset",
        error
      )
      guard playbackRequestRevision == requestID else { return false }
      pendingPlaybackRequest = .none
      await alert(ErrorKit.message(for: error))
      return false
    }
  }

  func clearMediaServicesRecoveryIfDeleted(_ episodeIDs: Set<Episode.ID>) {
    guard let episodeID = mediaServicesRecoveryEpisodeID, episodeIDs.contains(episodeID) else {
      return
    }
    mediaServicesRecoveryState = .none
  }

  func clearMediaServicesRecovery(for episodeID: Episode.ID) {
    guard mediaServicesRecoveryEpisodeID == episodeID else { return }
    mediaServicesRecoveryState = .none
  }

  func clearMediaServicesRecovery() {
    mediaServicesRecoveryState = .none
  }
}
