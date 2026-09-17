// Copyright Justin Bishop, 2025

import AVFoundation
import FactoryKit
import Foundation
import Logging
import Tagged

extension PlayManager {

  // MARK: - Playback Recovery

  func handlePlaybackFailure(preserving revision: UUID? = nil) async {
    let requestID = revision ?? playbackRequestRevision
    guard playbackRequestRevision == requestID else { return }
    Self.log.info("handlePlaybackFailure: recovering from AVPlayerItem failure")

    guard let episodeID = sharedState.onDeck?.id else {
      Self.log.warning("handlePlaybackFailure: no episode on deck to recover")
      return
    }

    await podAVPlayer.savePosition()
    guard playbackRequestRevision == requestID else { return }
    await logFailureDiagnostics(episodeID)
    guard playbackRequestRevision == requestID else { return }
    let recoveryRequestID = UUID()
    await stop(requestID: recoveryRequestID)
    guard playbackRequestRevision == recoveryRequestID else { return }

    // Attempt auto-recovery unless we just tried for this same episode
    let shouldAttemptRecovery: Bool
    if let lastRecoveryAttempt,
      lastRecoveryAttempt.episodeID == episodeID,
      Date().timeIntervalSince(lastRecoveryAttempt.time) < recoveryDebounceInterval
    {
      shouldAttemptRecovery = false
    } else {
      shouldAttemptRecovery = true
    }

    if shouldAttemptRecovery {
      do {
        let podcastEpisode = try await repo.podcastEpisode(episodeID)
        guard playbackRequestRevision == recoveryRequestID else { return }
        guard let podcastEpisode else {
          Self.log.warning("handlePlaybackFailure: episode \(episodeID) no longer exists")
          return
        }

        Self.log.info(
          "handlePlaybackFailure: attempting auto-recovery for \(podcastEpisode.toString)"
        )
        lastRecoveryAttempt = (episodeID, Date())
        let result = try await play(
          podcastEpisode,
          replacing: recoveryRequestID,
          requestID: recoveryRequestID
        )
        guard playbackRequestRevision == recoveryRequestID else { return }
        switch result {
        case .ready:
          Self.log.info("handlePlaybackFailure: auto-recovery succeeded")
          return
        case .superseded:
          return
        case .unavailable:
          Self.log.warning("handlePlaybackFailure: auto-recovery load remained deferred")
        }
      } catch {
        Self.log.caughtError(
          "handlePlaybackFailure: auto-recovery failed",
          error,
          level: .warning
        )
      }
    } else {
      Self.log.warning(
        "handlePlaybackFailure: skipping auto-recovery, already attempted for \(episodeID)"
      )
    }

    guard playbackRequestRevision == recoveryRequestID else { return }
    pendingPlaybackRequest = .none
    let returnedToQueue: Bool
    do {
      returnedToQueue = try await queue.unshift(episodeID) {
        self.playbackRequestRevision == recoveryRequestID
      }
    } catch {
      Self.log.caughtError(
        "handlePlaybackFailure: failed to return episode \(episodeID) to queue",
        error
      )
      returnedToQueue = false
    }

    await presentPlaybackFailure(returnedToQueue: returnedToQueue, preserving: recoveryRequestID)
  }

  @MainActor private func presentPlaybackFailure(returnedToQueue: Bool, preserving requestID: UUID)
  {
    guard playbackRequestRevision == requestID else { return }
    let message =
      if returnedToQueue {
        "Playback failed unexpectedly. The episode has been returned to your queue."
      } else {
        "Playback failed unexpectedly. The episode could not be returned to your queue."
      }
    Container.shared.alert()(message)
  }

  func activateAudioSessionForLoad() throws -> Bool {
    do {
      try Container.shared.setAudioSessionActive()(true)
      return true
    } catch {
      let nsError = error as NSError
      guard nsError.domain == NSOSStatusErrorDomain,
        nsError.code == AVAudioSession.ErrorCode.cannotInterruptOthers.rawValue
      else {
        throw error
      }

      Self.log.info(
        "performLoad: audio session activation deferred because another session owns audio"
      )
      return false
    }
  }

  private func logFailureDiagnostics(_ episodeID: Episode.ID) async {
    // Check cached file integrity
    let podcastEpisode: PodcastEpisode?
    do {
      podcastEpisode = try await repo.podcastEpisode(episodeID)
    } catch {
      Self.log.caughtError(
        "logFailureDiagnostics: failed to fetch episode \(episodeID)",
        error
      )
      podcastEpisode = nil
    }

    if let podcastEpisode, let cachedURL = podcastEpisode.episode.cachedURL {
      if fileManager.fileExists(at: cachedURL.rawValue) {
        do {
          let size = try fileManager.fileSize(for: cachedURL.rawValue)
          Self.log.info("logFailureDiagnostics: cached file exists, size: \(size) bytes")
        } catch {
          Self.log.caughtError(
            "logFailureDiagnostics: failed to get file size at \(cachedURL)",
            error
          )
        }
      } else {
        Self.log.warning("logFailureDiagnostics: cached file MISSING at \(cachedURL)")
      }
    } else {
      Self.log.info("logFailureDiagnostics: episode not cached")
    }

    // Log audio session state
    let session = AVAudioSession.sharedInstance()
    Self.log.info(
      """
      logFailureDiagnostics: audio session state
        category: \(session.category.rawValue)
        mode: \(session.mode.rawValue)
        isOtherAudioPlaying: \(session.isOtherAudioPlaying)
        currentRoute: \(session.currentRoute.outputs.map(\.portType.rawValue))
      """
    )
  }
}
