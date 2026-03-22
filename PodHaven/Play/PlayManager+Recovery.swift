// Copyright Justin Bishop, 2025

import AVFoundation

extension PlayManager {

  // MARK: - Playback Recovery

  func handlePlaybackFailure() async {
    Self.log.info("handlePlaybackFailure: recovering from AVPlayerItem failure")

    guard let episodeID = sharedState.onDeck?.id else {
      Self.log.warning("handlePlaybackFailure: no episode on deck to recover")
      return
    }

    await podAVPlayer.savePosition()
    await logFailureDiagnostics(episodeID)
    await stop()

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
      lastRecoveryAttempt = (episodeID, Date())
      do {
        guard let podcastEpisode = try await repo.podcastEpisode(episodeID) else {
          Self.log.warning("handlePlaybackFailure: episode \(episodeID) no longer exists")
          return
        }

        Self.log.info(
          "handlePlaybackFailure: attempting auto-recovery for \(podcastEpisode.toString)"
        )
        try await load(podcastEpisode)
        await play()
        Self.log.info("handlePlaybackFailure: auto-recovery succeeded")
        return
      } catch {
        Self.log.caughtError(
          "handlePlaybackFailure: auto-recovery failed",
          error,
          remarkable: .warning
        )
      }
    } else {
      Self.log.warning(
        "handlePlaybackFailure: skipping auto-recovery, already attempted for \(episodeID)"
      )
    }

    // Fall back to returning episode to queue
    do {
      try await queue.unshift(episodeID)
    } catch {
      Self.log.caughtError(
        "handlePlaybackFailure: failed to return episode \(episodeID) to queue",
        error
      )
    }

    await alert("Playback failed unexpectedly. The episode has been returned to your queue.")
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
