// Copyright Justin Bishop, 2025

import AVFoundation
import FactoryKit
import Foundation
import Logging
import SwiftUI
import Tagged

enum UndoSeekDirection {
  case backward
  case forward
}

@Observable @MainActor class PlayBarViewModel {
  @ObservationIgnored @DynamicInjected(\.alert) private var alert
  @ObservationIgnored @DynamicInjected(\.playManager) private var playManager
  @ObservationIgnored @DynamicInjected(\.queue) private var queue
  @ObservationIgnored @DynamicInjected(\.repo) private var repo
  @ObservationIgnored @DynamicInjected(\.sharedState) private var sharedState
  @ObservationIgnored @DynamicInjected(\.sleeper) private var sleeper
  @ObservationIgnored @DynamicInjected(\.userSettings) private var userSettings

  private static let log = Log.as(LogSubsystem.PlayBar.main)

  // Only surface the max-playback marker and swap the finish button for
  // jump-to-max when the peak is at least this far ahead of the scrubber.
  // Tweak after eyeballing in the simulator.
  private static let jumpToMaxMinDeltaSeconds: Double = 20

  // MARK: - State Management

  var isLoading: Bool { sharedState.playbackStatus.loading }
  var isPlaying: Bool { sharedState.playbackStatus.playing }
  var isStopped: Bool { sharedState.playbackStatus.stopped }
  var isWaiting: Bool { sharedState.playbackStatus.waiting }

  var undoSeekDirection: UndoSeekDirection?
  @ObservationIgnored private var undoCandidate: (episodeID: Episode.ID, time: Double)?
  @ObservationIgnored private var hideUndoButtonTask: Task<Void, Never>?

  var episodeImage: UIImage? { sharedState.onDeck?.artwork }
  var loadingEpisodeTitle: String { sharedState.playbackStatus.loadingTitle ?? "Unknown" }

  var playbackRate: Binding<Float> {
    Binding(
      get: { self.sharedState.playRate },
      set: { newRate in
        Task { [weak self] in
          guard let self else { return }

          Self.log.debug("Setting playback rate to \(newRate)")
          await playManager.setRate(newRate)
        }
      }
    )
  }

  var duration: CMTime {
    (sharedState.onDeck?.duration ?? .zero).safe
  }

  // MARK: - Chapters

  var chapters: [CMTime]? { sharedState.onDeck?.chapters }

  var hasChapters: Bool { chapters != nil }

  var chapterPositions: [Double]? { chapters?.map { $0.seconds } }

  // MARK: - Max Playback Position

  // Live peak: fall back to the scrubber value in case the in-memory OnDeck
  // lags behind (e.g., a scrub just happened and the update is in-flight).
  var maxPlaybackTime: Double {
    Swift.max(
      (sharedState.onDeck?.maxPlaybackTime ?? .zero).safe.seconds,
      sliderValue
    )
  }

  var canJumpToMaxPlayback: Bool {
    (maxPlaybackTime - sliderValue) > Self.jumpToMaxMinDeltaSeconds
  }

  var canGoToNextChapter: Bool {
    guard let chapters, !chapters.isEmpty else { return false }
    let currentSeconds = sliderValue
    return chapters.contains { $0.seconds > currentSeconds }
  }

  var isDragging = false {
    didSet {
      if isDragging, !oldValue {
        onSliderSeekStarted()
      } else if !isDragging, oldValue {
        onSliderSeekEnded()
      }
    }
  }

  private var _sliderValue: Double = 0
  var sliderValue: Double {
    get { isDragging ? _sliderValue : (sharedState.onDeck?.currentTime ?? .zero).safe.seconds }
    set {
      self._sliderValue = newValue
      Task { [weak self] in
        guard let self else { return }
        await playManager.seek(to: CMTime.seconds(_sliderValue))
      }
    }
  }

  // MARK: - Actions

  func playOrPause() {
    if isPlaying {
      Task { [weak self] in
        guard let self else { return }
        await playManager.pause()
      }
    } else {
      Task { [weak self] in
        guard let self else { return }
        await playManager.play()
      }
    }
  }

  func seekBackward() {
    Task { [weak self] in
      guard let self else { return }
      Self.log.debug("Seeking backward")
      await playManager.seekBackward()
    }
  }

  func seekForward() {
    Task { [weak self] in
      guard let self else { return }
      Self.log.debug("Seeking forward")
      await playManager.seekForward()
    }
  }

  func goToPreviousChapter() {
    Task { [weak self] in
      guard let self else { return }
      Self.log.debug("Going to previous chapter")
      await playManager.seekToPreviousChapter()
    }
  }

  func goToNextChapter() {
    Task { [weak self] in
      guard let self else { return }
      Self.log.debug("Going to next chapter")
      await playManager.seekToNextChapter()
    }
  }

  func jumpToMaxPlayback() {
    let target = maxPlaybackTime
    Task { [weak self] in
      guard let self else { return }
      Self.log.debug("Jumping to max playback position: \(target)")
      await playManager.seek(to: CMTime.seconds(target))
    }
  }

  func finishEpisode() {
    Task { [weak self] in
      guard let self else { return }

      Self.log.debug("Skipping to next episode")

      guard let currentEpisode = sharedState.onDeck else {
        Self.log.warning("No current episode to skip")
        return
      }

      await playManager.finishEpisode(currentEpisode.id)
    }
  }

  // MARK: - Rating

  func rate(_ rating: EpisodeRating?) {
    guard let onDeck = sharedState.onDeck else {
      Self.log.warning("No on-deck episode to rate")
      return
    }
    guard onDeck.rating != rating else { return }

    Task { [weak self] in
      guard let self else { return }

      do {
        try await repo.updateRating(onDeck.id, rating: rating)
      } catch {
        Self.log.caughtError("rate: failed for \(onDeck.title)", error)
        guard ErrorKit.isRemarkable(error) else { return }
        alert(ErrorKit.message(for: error))
      }
    }
  }

  // MARK: - Undo Seek

  private func onSliderSeekStarted() {
    guard userSettings.enableUndoSeek else { return }

    // Cancel any pending hide task to prevent it from firing mid-drag
    cancelHideUndoButtonTask()

    if let undoCandidate, sharedState.onDeck?.id != undoCandidate.episodeID {
      Self.log.debug("Clearing undo candidate: episode changed")
      self.undoCandidate = nil
    }

    // Only capture position if we don't already have one (first seek in a chain)
    if undoCandidate == nil, let onDeck = sharedState.onDeck {
      let time = onDeck.currentTime.safe.seconds
      undoCandidate = (episodeID: onDeck.id, time: time)
      Self.log.debug("Captured undo candidate: episode \(onDeck.id), time \(time)")
    }
  }

  private func onSliderSeekEnded() {
    guard userSettings.enableUndoSeek else { return }

    guard let undoCandidate else { return }
    guard sharedState.onDeck?.id == undoCandidate.episodeID else {
      Self.log.debug("Clearing undo state: episode changed during seek")
      clearUndoState()
      return
    }

    let currentTime = (sharedState.onDeck?.currentTime ?? .zero).safe.seconds
    guard currentTime != undoCandidate.time else {
      Self.log.debug("Clearing undo state: scrub landed at the original position (\(currentTime))")
      clearUndoState()
      return
    }

    // If the scrub went backward, undoing jumps forward.
    let direction: UndoSeekDirection = undoCandidate.time > currentTime ? .forward : .backward
    undoSeekDirection = direction
    Self.log.debug(
      "Showing undo button (direction: \(direction), from \(currentTime) to \(undoCandidate.time))"
    )

    hideUndoButtonTask = Task { [weak self] in
      guard let self else { return }

      do {
        try await sleeper.sleep(for: .seconds(3))
        try Task.checkCancellation()

        clearUndoState()
        Self.log.debug("Hiding undo button after timeout")
      } catch {
        // Cancelled is expected if user seeks again or taps undo.
        Self.log.debug("Undo hide task cancelled")
      }
    }
  }

  func undoSeek() {
    guard let candidate = undoCandidate else { return }

    guard sharedState.onDeck?.id == candidate.episodeID
    else {
      Self.log.debug("Undo skipped: episode changed")
      clearUndoState()
      return
    }

    Self.log.debug("Undoing seek, returning to position: \(candidate.time)")

    clearUndoState()

    Task { [weak self] in
      guard let self else { return }
      await playManager.seek(to: CMTime.seconds(candidate.time))
    }
  }

  private func clearUndoState() {
    cancelHideUndoButtonTask()
    undoSeekDirection = nil
    undoCandidate = nil
  }

  private func cancelHideUndoButtonTask() {
    hideUndoButtonTask?.cancel()
    hideUndoButtonTask = nil
  }
}
