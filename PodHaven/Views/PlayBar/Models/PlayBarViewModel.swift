// Copyright Justin Bishop, 2025

import AVFoundation
import FactoryKit
import Foundation
import GRDB
import Logging
import SwiftUI
import Tagged

enum UndoSeekDirection {
  case backward
  case forward
}

@Observable @MainActor class PlayBarViewModel {
  @ObservationIgnored private let container = Container.shared
  @ObservationIgnored @DynamicInjected(\.alert) private var alert
  @ObservationIgnored @DynamicInjected(\.observatory) private var observatory
  @ObservationIgnored @DynamicInjected(\.playManager) private var playManager
  @ObservationIgnored @DynamicInjected(\.queue) private var queue
  @ObservationIgnored @DynamicInjected(\.repo) private var repo
  @ObservationIgnored @DynamicInjected(\.sharedState) private var sharedState
  @ObservationIgnored @DynamicInjected(\.sleeper) private var sleeper
  @ObservationIgnored @DynamicInjected(\.transcriptionAvailability)
  private var transcriptionAvailability
  @ObservationIgnored @DynamicInjected(\.transcriptionProcessor) private var transcriptionProcessor
  @ObservationIgnored @DynamicInjected(\.transcriptionQueue) private var transcriptionQueue
  @ObservationIgnored @DynamicInjected(\.userSettings) private var userSettings

  private static let log = Log.as(LogSubsystem.PlayBar.main)

  // Only surface the max-playback marker and swap the finish button for
  // jump-to-max when the peak is at least this far ahead of the scrubber.
  // Tweak after eyeballing in the simulator.
  private static let jumpToMaxMinDeltaSeconds: Double = 20

  func withDependencies<Value>(_ operation: () -> Value) -> Value {
    Container.$shared.withValue(container, operation: operation)
  }

  // MARK: - State Management

  var isLoading: Bool { withDependencies { sharedState.playbackStatus.loading } }
  var isPlaying: Bool { withDependencies { sharedState.playbackStatus.playing } }
  var isStopped: Bool { withDependencies { sharedState.playbackStatus.stopped } }
  var isWaiting: Bool { withDependencies { sharedState.playbackStatus.waiting } }

  var undoSeekDirection: UndoSeekDirection?
  @ObservationIgnored private var undoCandidate: (episodeID: Episode.ID, time: Double)?
  @ObservationIgnored private var hideUndoButtonTask: Task<Void, Never>?
  private var transcriptionCheckpoint: (episodeID: Episode.ID, progress: Double)?
  private var transcriptEpisodeID: Episode.ID?
  private var storedTranscript: Transcript?

  var episodeImage: UIImage? { withDependencies { sharedState.onDeck?.artwork } }
  var loadingEpisodeTitle: String {
    withDependencies { sharedState.playbackStatus.loadingTitle ?? "Unknown" }
  }

  var playbackRate: Binding<Float> {
    Binding(
      get: { self.withDependencies { self.sharedState.playRate } },
      set: { newRate in
        self.withDependencies {
          _ = Task { [weak self] in
            guard let self else { return }

            Self.log.debug("Setting playback rate to \(newRate)")
            await playManager.setRate(newRate)
          }
        }
      }
    )
  }

  var silenceMode: SilenceMode { withDependencies { sharedState.effectiveSilenceMode } }

  func selectSilenceMode(_ mode: SilenceMode) {
    withDependencies {
      guard let episodeID = sharedState.currentEpisodeID else { return }
      sharedState.$silenceOverride.new(SilenceOverride(episodeID: episodeID, mode: mode))
    }
  }

  var duration: CMTime {
    withDependencies {
      (sharedState.onDeck?.duration ?? .zero).safe
    }
  }

  // MARK: - Chapters

  var chapters: [CMTime]? { withDependencies { sharedState.onDeck?.chapters } }

  var hasChapters: Bool { chapters != nil }

  var chapterPositions: [Double]? { chapters?.map { $0.seconds } }

  // MARK: - Max Playback Position

  // Live peak: fall back to the scrubber value in case the in-memory OnDeck
  // lags behind (e.g., a scrub just happened and the update is in-flight).
  var maxPlaybackTime: Double {
    withDependencies {
      Swift.max(
        (sharedState.onDeck?.maxPlaybackTime ?? .zero).safe.seconds,
        sliderValue
      )
    }
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
    get {
      withDependencies {
        isDragging ? _sliderValue : (sharedState.onDeck?.currentTime ?? .zero).safe.seconds
      }
    }
    set {
      withDependencies {
        self._sliderValue = newValue
        _ = Task { [weak self] in
          guard let self else { return }
          await playManager.seek(to: CMTime.seconds(_sliderValue))
        }
      }
    }
  }

  // MARK: - Actions

  func playOrPause() {
    withDependencies {
      if isPlaying {
        _ = Task { [weak self] in
          guard let self else { return }
          await playManager.pause()
        }
      } else {
        _ = Task { [weak self] in
          guard let self else { return }
          await playManager.play()
        }
      }
    }
  }

  func seekBackward() {
    withDependencies {
      _ = Task { [weak self] in
        guard let self else { return }
        Self.log.debug("Seeking backward")
        await playManager.seekBackward()
      }
    }
  }

  func seekForward() {
    withDependencies {
      _ = Task { [weak self] in
        guard let self else { return }
        Self.log.debug("Seeking forward")
        await playManager.seekForward()
      }
    }
  }

  func goToPreviousChapter() {
    withDependencies {
      _ = Task { [weak self] in
        guard let self else { return }
        Self.log.debug("Going to previous chapter")
        await playManager.seekToPreviousChapter()
      }
    }
  }

  func goToNextChapter() {
    withDependencies {
      _ = Task { [weak self] in
        guard let self else { return }
        Self.log.debug("Going to next chapter")
        await playManager.seekToNextChapter()
      }
    }
  }

  func jumpToMaxPlayback() {
    withDependencies {
      let target = maxPlaybackTime
      _ = Task { [weak self] in
        guard let self else { return }
        Self.log.debug("Jumping to max playback position: \(target)")
        await playManager.seek(to: CMTime.seconds(target))
      }
    }
  }

  func finishEpisode() {
    withDependencies {
      _ = Task { [weak self] in
        guard let self else { return }

        Self.log.debug("Skipping to next episode")

        guard let currentEpisode = sharedState.onDeck else {
          Self.log.warning("No current episode to skip")
          return
        }

        await playManager.finishEpisode(currentEpisode.id)
      }
    }
  }

  // MARK: - Stop After Episode

  func toggleStopAfterCurrentEpisode() {
    withDependencies {
      let enabled = !sharedState.stopAfterCurrentEpisode
      Self.log.debug("Toggling stopAfterCurrentEpisode to \(enabled)")
      sharedState.setStopAfterCurrentEpisode(enabled)
    }
  }

  // MARK: - Transcription

  var isTranscriptionAvailable: Bool {
    withDependencies {
      transcriptionAvailability.isAvailable
    }
  }

  var transcriptionStatus: TranscriptionStatus {
    withDependencies {
      guard let onDeck = sharedState.onDeck else { return .none }
      let checkpointProgress: Double?
      if let transcriptionCheckpoint,
        transcriptionCheckpoint.episodeID == onDeck.id
      {
        checkpointProgress = transcriptionCheckpoint.progress
      } else {
        checkpointProgress = nil
      }
      return transcriptionQueue.status(
        for: onDeck.id,
        hasTranscript: onDeck.hasTranscript,
        checkpointProgress: checkpointProgress
      )
    }
  }

  var transcript: Transcript? {
    withDependencies {
      guard transcriptEpisodeID == sharedState.onDeck?.id else { return nil }
      return storedTranscript
    }
  }

  var canExpandTranscript: Bool {
    transcript?.segments.isEmpty == false
  }

  func transcribe() {
    withDependencies {
      guard
        let onDeck = sharedState.onDeck,
        isTranscriptionAvailable,
        transcriptionStatus.canTranscribe
      else { return }

      _ = Task { [weak self] in
        guard let self else { return }
        do {
          let replacesPublisherTranscript =
            try await repo.episode(onDeck.id)?.publisherTranscriptSource != nil
          if replacesPublisherTranscript {
            try await transcriptionProcessor.enqueuePublisherReplacement(
              onDeck.id
            )
          } else {
            try await transcriptionProcessor.enqueue(onDeck.id)
          }
        } catch let error as TranscriptionQueueError {
          Self.log.caughtError(
            "transcribe: rejected for \(onDeck.title)",
            error,
            level: .notice
          )
          alert(
            title: error.alertTitle,
            ErrorKit.message(for: error)
          )
        } catch {
          Self.log.caughtError("transcribe: failed for \(onDeck.title)", error)
          guard ErrorKit.isRemarkable(error) else { return }
          alert(ErrorKit.message(for: error))
        }
      }
    }
  }

  func pauseTranscription() {
    withDependencies {
      guard let onDeck = sharedState.onDeck, transcriptionStatus.canPause else { return }

      _ = Task { [weak self] in
        guard let self else { return }
        do {
          try await transcriptionProcessor.pause(onDeck.id)
        } catch {
          Self.log.caughtError("pauseTranscription: failed for \(onDeck.title)", error)
          guard ErrorKit.isRemarkable(error) else { return }
          alert(ErrorKit.message(for: error))
        }
      }
    }
  }

  func observeTranscriptionCheckpoint() async {
    await Container.$shared.withValue(container) {
      guard let episodeID = sharedState.onDeck?.id else {
        transcriptionCheckpoint = nil
        return
      }

      do {
        for try await checkpoint in observatory.transcriptionCheckpoint(episodeID) {
          try Task.checkCancellation()
          guard sharedState.onDeck?.id == episodeID else { return }
          if let checkpoint {
            transcriptionCheckpoint = (episodeID, checkpoint.progress)
          } else {
            transcriptionCheckpoint = nil
          }
        }
      } catch {
        if sharedState.onDeck?.id == episodeID {
          transcriptionCheckpoint = nil
        }
        Self.log.caughtError(
          "observeTranscriptionCheckpoint: failed for \(episodeID)",
          error
        )
      }
    }
  }

  func observeTranscript() async {
    await Container.$shared.withValue(container) {
      guard let episodeID = sharedState.onDeck?.id else {
        transcriptEpisodeID = nil
        storedTranscript = nil
        return
      }

      if transcriptEpisodeID != episodeID {
        transcriptEpisodeID = episodeID
        storedTranscript = nil
      }
      do {
        for try await transcript in observatory.transcript(episodeID) {
          try Task.checkCancellation()
          guard sharedState.onDeck?.id == episodeID else { return }
          transcriptEpisodeID = episodeID
          storedTranscript = transcript
        }
      } catch {
        if sharedState.onDeck?.id == episodeID {
          transcriptEpisodeID = episodeID
          storedTranscript = nil
        }
        Self.log.caughtError("observeTranscript: failed for \(episodeID)", error)
      }
    }
  }

  // MARK: - Rating

  func rate(_ rating: EpisodeRating?) {
    withDependencies {
      guard let onDeck = sharedState.onDeck else {
        Self.log.warning("No on-deck episode to rate")
        return
      }
      guard onDeck.rating != rating else { return }

      _ = Task { [weak self] in
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
  }

  // MARK: - Undo Seek

  private func onSliderSeekStarted() {
    withDependencies {
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
  }

  private func onSliderSeekEnded() {
    withDependencies {
      guard userSettings.enableUndoSeek else { return }

      guard let undoCandidate else { return }
      guard sharedState.onDeck?.id == undoCandidate.episodeID else {
        Self.log.debug("Clearing undo state: episode changed during seek")
        clearUndoState()
        return
      }

      let currentTime = (sharedState.onDeck?.currentTime ?? .zero).safe.seconds
      guard currentTime != undoCandidate.time else {
        Self.log.debug(
          "Clearing undo state: scrub landed at the original position (\(currentTime))"
        )
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
  }

  func undoSeek() {
    withDependencies {
      guard let candidate = undoCandidate else { return }

      guard sharedState.onDeck?.id == candidate.episodeID
      else {
        Self.log.debug("Undo skipped: episode changed")
        clearUndoState()
        return
      }

      Self.log.debug("Undoing seek, returning to position: \(candidate.time)")

      clearUndoState()

      _ = Task { [weak self] in
        guard let self else { return }
        await playManager.seek(to: CMTime.seconds(candidate.time))
      }
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
