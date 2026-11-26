// Copyright Justin Bishop, 2026

import AVFoundation
import Foundation
import Logging

extension PlayManager {
  // MARK: - Seeking

  func seekForward(_ interval: TimeInterval? = nil) async {
    let duration = interval ?? userSettings.skipForwardInterval
    let currentTime = await currentPlaybackTime()
    await seek(to: currentTime + CMTime.seconds(duration))
  }

  func seekBackward(_ interval: TimeInterval? = nil) async {
    let duration = interval ?? userSettings.skipBackwardInterval
    let currentTime = await currentPlaybackTime()
    await seek(to: currentTime - CMTime.seconds(duration))
  }

  func currentPlaybackTime() async -> CMTime {
    if let onDeck = await onDeckAwaitingRecoveryReload() { return onDeck.currentTime }
    return await podAVPlayer.currentTime()
  }

  func seek(to time: CMTime) async {
    guard time.isNumeric else {
      Self.log.warning("seek: ignoring non-numeric target \(time)")
      return
    }
    cancelWidgetRouteRecovery(reason: "userSeek")
    let playerTime = await podAVPlayer.currentTime().safe
    let recoveryEpisodeID = await onDeckAwaitingRecoveryReload()?.id
    let currentTime = max(playerTime, sharedState.onDeck?.currentTime.safe ?? .zero)
    let duration = sharedState.onDeck?.duration.safe ?? .zero
    // The duration is an estimate, so it stops capping seeks once the live or restored
    // position runs past it.
    let target =
      duration > .zero && currentTime <= duration
      ? time.clamped(to: .zero...duration) : max(time, .zero)
    NowPlayingInfo.setCurrentTime(target)
    guard let recoveryEpisodeID else { return await podAVPlayer.seek(to: target) }

    Self.log.debug("seek: \(target) for episode \(recoveryEpisodeID) awaiting recovery reload")
    stateManager.setCurrentTime(target)
    // Saves run in seek order, so a reload resumes from the latest seek.
    let previousSave = onDeckRecoveryPositionSave
    let save = Task {
      await previousSave?.value
      do {
        try await repo.updateCurrentTime(recoveryEpisodeID, currentTime: target)
      } catch {
        Self.log.caughtError(
          "seek: failed to save \(target) for recovery episode \(recoveryEpisodeID)",
          error
        )
      }
    }
    onDeckRecoveryPositionSave = save
    await save.value
  }

  // MARK: - Chapter Navigation

  func seekToNextChapter() async {
    guard let chapters = sharedState.onDeck?.chapters, !chapters.isEmpty else {
      await seekForward()
      return
    }

    let currentSeconds = (sharedState.onDeck?.currentTime ?? .zero).seconds
    if let nextChapter = chapters.first(where: { $0.seconds > currentSeconds }) {
      await seek(to: nextChapter)
    } else {
      await finishEpisode()
    }
  }

  func seekToPreviousChapter() async {
    guard let chapters = sharedState.onDeck?.chapters, !chapters.isEmpty else {
      await seekBackward()
      return
    }

    let currentSeconds = (sharedState.onDeck?.currentTime ?? .zero).seconds
    let previousChapters = chapters.filter { $0.seconds < currentSeconds }

    let targetTime: CMTime
    if let nearestPrevious = previousChapters.last {
      if currentSeconds - nearestPrevious.seconds < 2 {
        targetTime =
          previousChapters.count > 1 ? previousChapters[previousChapters.count - 2] : .zero
      } else {
        targetTime = nearestPrevious
      }
    } else {
      targetTime = .zero
    }

    await seek(to: targetTime)
  }

  // Incoming command from user input (in contrast to setPlaybackRate(_:)).
  func setRate(_ rate: Float) async {
    Assert.precondition(rate > 0, "Setting playback rate to 0?")

    sharedState.setPlayRate(rate)
    await podAVPlayer.setRate(rate)
  }
}
