// Copyright Justin Bishop, 2025

import AVFoundation
import FactoryKit
import Foundation
import Logging
import SwiftUI

@Observable @MainActor class PlayBarViewModel {
  @ObservationIgnored @DynamicInjected(\.playManager) private var playManager
  @ObservationIgnored @DynamicInjected(\.queue) private var queue
  @ObservationIgnored @DynamicInjected(\.sharedState) private var sharedState
  @ObservationIgnored @DynamicInjected(\.sleeper) private var sleeper
  @ObservationIgnored @DynamicInjected(\.userSettings) private var userSettings

  private static let log = Log.as(LogSubsystem.PlayBar.main)

  // MARK: - State Management

  var playBarSheetIsPresented = false

  var isLoading: Bool { sharedState.playbackStatus.loading }
  var isPlaying: Bool { sharedState.playbackStatus.playing }
  var isStopped: Bool { sharedState.playbackStatus.stopped }
  var isWaiting: Bool { sharedState.playbackStatus.waiting }

  var showUndoButton = false
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

  func finishEpisode() {
    Task { [weak self] in
      guard let self else { return }

      Self.log.debug("Skipping to next episode")

      // Get the current episode
      guard let currentEpisode = sharedState.onDeck else {
        Self.log.warning("No current episode to skip")
        return
      }

      await playManager.finishEpisode(currentEpisode.id)
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

    // Only show undo if we have a valid candidate for the current episode
    guard let undoCandidate else { return }
    guard sharedState.onDeck?.id == undoCandidate.episodeID else {
      Self.log.debug("Clearing undo state: episode changed during seek")
      clearUndoState()
      return
    }

    // Show the undo button
    showUndoButton = true
    Self.log.debug("Showing undo button")

    hideUndoButtonTask = Task { [weak self] in
      guard let self else { return }

      do {
        try await sleeper.sleep(for: .seconds(3))

        // Only hide if not cancelled
        try Task.checkCancellation()

        clearUndoState()
        Self.log.debug("Hiding undo button after timeout")
      } catch {
        // Task was cancelled, which is expected if user seeks again or taps undo
        Self.log.debug("Undo hide task cancelled")
      }
    }
  }

  func undoSeek() {
    guard let candidate = undoCandidate else { return }

    // Only allow undo if we're still on the same episode
    guard sharedState.onDeck?.id == candidate.episodeID
    else {
      Self.log.debug("Undo skipped: episode changed")
      clearUndoState()
      return
    }

    Self.log.debug("Undoing seek, returning to position: \(candidate.time)")

    // Cancel the hide task and reset state immediately
    clearUndoState()

    // Seek back to the original position
    Task { [weak self] in
      guard let self else { return }
      await playManager.seek(to: CMTime.seconds(candidate.time))
    }
  }

  private func clearUndoState() {
    cancelHideUndoButtonTask()
    showUndoButton = false
    undoCandidate = nil
  }

  private func cancelHideUndoButtonTask() {
    hideUndoButtonTask?.cancel()
    hideUndoButtonTask = nil
  }
}
