// Copyright Justin Bishop, 2026

import AVFoundation
import Foundation
import Logging

extension PlayManager {
  // MARK: - Seeking

  func seekForward(_ interval: TimeInterval? = nil) async {
    let duration = interval ?? userSettings.skipForwardInterval
    let currentTime = await podAVPlayer.currentTime()
    await seek(to: currentTime + CMTime.seconds(duration))
  }

  func seekBackward(_ interval: TimeInterval? = nil) async {
    let duration = interval ?? userSettings.skipBackwardInterval
    let currentTime = await podAVPlayer.currentTime()
    await seek(to: currentTime - CMTime.seconds(duration))
  }

  func seek(to time: CMTime) async {
    guard time.isNumeric else {
      Self.log.warning("seek: ignoring non-numeric target \(time)")
      return
    }
    cancelWidgetRouteRecovery(reason: "userSeek")
    let duration = sharedState.onDeck?.duration.safe ?? .zero
    let target = duration > .zero ? time.clamped(to: .zero...duration) : max(time, .zero)
    NowPlayingInfo.setCurrentTime(target)
    await podAVPlayer.seek(to: target)
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
