// Copyright Justin Bishop, 2026

import FactoryKit
import Foundation
import Logging
import SwiftUI
import Tagged

// MARK: - Container

extension Container {
  var transcriptionProcessor: Factory<TranscriptionProcessor> {
    Factory(self) { TranscriptionProcessor() }.scope(.cached)
  }
}

// MARK: - TranscriptionProcessor

// Drains the persisted TranscriptionQueue one episode at a time off the main
// actor while the app is foregrounded, and registers a discretionary
// BGProcessingTask (mirroring EmbeddingProcessor) so iOS can drain it in the
// background too. Ordinary backgrounding preserves in-flight foreground work;
// the persisted queue retains its head for retry after cancellation or expiry.
struct TranscriptionProcessor: Sendable {
  @DynamicInjected(\.cacheManager) private var cacheManager
  @DynamicInjected(\.continuousClockNow) private var continuousClockNow
  @DynamicInjected(\.repo) private var repo
  @DynamicInjected(\.taskPriority) private var taskPriority
  @DynamicInjected(\.transcriber) private var transcriber
  @DynamicInjected(\.transcriptionQueue) private var transcriptionQueue

  private static let log = Log.as(LogSubsystem.Transcription.processor)

  private static let backgroundTaskIdentifier = "\(AppInfo.bundleIdentifier).transcription"

  private let backgroundTaskScheduler: BackgroundTaskScheduler
  private let processingTask = ThreadSafe<Task<Void, Never>?>(nil)

  private enum ForegroundState {
    case active
    case background
  }

  private let foregroundState = ThreadSafe(ForegroundState.background)

  fileprivate init() {
    let queue = Container.shared.transcriptionQueue()
    backgroundTaskScheduler = BackgroundTaskScheduler(
      identifier: Self.backgroundTaskIdentifier,
      cadence: .minutes(1),
      taskType: .processing(requiresNetworkConnectivity: false),
      schedulingMode: .onDemand { !queue.episodeIDs.isEmpty },
      expirationBehavior: .awaitCancellation
    )
  }

  // MARK: - Background Task

  // iOS-granted background drain, mirroring EmbeddingProcessor. The persisted
  // queue survives expiry, so the next grant or foreground activation retries
  // the retained head.
  func register() {
    backgroundTaskScheduler.register { complete in
      let runID = UUID().uuidString
      let startedAt = continuousClockNow()
      Self.log.info(
        """
        transcriptionTelemetry event=backgroundRunStarted runID=\(runID) \
        queuedEpisodes=\(transcriptionQueue.episodeIDs.count)
        """
      )
      do {
        try await drain(.background, runID: runID)
      } catch is CancellationError {
        if case .background = foregroundState(), let foregroundTask = stop() {
          await foregroundTask.value
        }
        Self.log.info(
          """
          transcriptionTelemetry event=backgroundRunExpired runID=\(runID) \
          wallSeconds=\((continuousClockNow() - startedAt).asTimeInterval) \
          remainingEpisodes=\(transcriptionQueue.episodeIDs.count)
          """
        )
        complete(false)
        return
      } catch {
        Self.log.caughtError(
          """
          transcriptionTelemetry event=backgroundRunFailed runID=\(runID) \
          wallSeconds=\((continuousClockNow() - startedAt).asTimeInterval) \
          remainingEpisodes=\(transcriptionQueue.episodeIDs.count)
          """,
          error
        )
        complete(false)
        return
      }
      backgroundTaskScheduler.scheduleNext()
      Self.log.info(
        """
        transcriptionTelemetry event=backgroundRunCompleted runID=\(runID) \
        wallSeconds=\((continuousClockNow() - startedAt).asTimeInterval) \
        remainingEpisodes=\(transcriptionQueue.episodeIDs.count)
        """
      )
      complete(true)
    }
  }

  // MARK: - Scene Phase

  func handleScenePhaseChange(to scenePhase: ScenePhase) {
    switch scenePhase {
    case .active:
      Self.log.debug("activated")
      foregroundState(.active)
      start()
    case .background:
      Self.log.debug("backgrounded")
      foregroundState(.background)
      if transcriptionQueue.progress.isEmpty {
        stop()
      }
      backgroundTaskScheduler.scheduleNext()
    default:
      break
    }
  }

  // MARK: - Loop

  private func start() {
    processingTask { task in
      guard task == nil else { return }
      task = Task(priority: taskPriority(.background)) {
        defer { foregroundTaskFinished() }
        do {
          try await drain(.foreground, runID: UUID().uuidString)
        } catch is CancellationError {
          return
        } catch {
          Self.log.caughtError("Foreground transcription drain failed", error)
        }
      }
    }
  }

  @discardableResult
  private func stop() -> Task<Void, Never>? {
    processingTask { task -> Task<Void, Never>? in
      task?.cancel()
      return task
    }
  }

  private func foregroundTaskFinished() {
    processingTask(nil)
    if case .active = foregroundState() {
      start()
    }
  }

  // The queue yields one claimed head at a time and owns exclusive consumer
  // access. Foreground waits for future work while a background grant returns
  // when the backlog empties.
  private func drain(_ mode: TranscriptionLogContext.Mode, runID: String) async throws {
    try await transcriptionQueue.withWorkStream { stream in
      if case .background = mode, transcriptionQueue.episodeIDs.isEmpty {
        return
      }

      for await episodeID in stream {
        try Task.checkCancellation()
        if case .foreground = mode, case .background = foregroundState() {
          return
        }
        try await processHead(
          episodeID,
          logContext: TranscriptionLogContext(
            runID: runID,
            mode: mode,
            episodeID: episodeID
          )
        )
        if case .foreground = mode, case .background = foregroundState() {
          return
        }
        if case .background = mode, transcriptionQueue.episodeIDs.isEmpty {
          return
        }
      }

      try Task.checkCancellation()
    }
  }

  // Processes one episode; rethrows CancellationError so callers can stop, and
  // records any other failure so the queue moves past a bad episode.
  private func processHead(
    _ episodeID: Episode.ID,
    logContext: TranscriptionLogContext
  ) async throws {
    let startedAt = continuousClockNow()
    Self.log.info(
      """
      transcriptionTelemetry event=episodeStarted \(logContext.fields) \
      queuedEpisodes=\(transcriptionQueue.episodeIDs.count)
      """
    )
    do {
      try await process(episodeID, logContext: logContext)
    } catch is CancellationError {
      let liveProgress = transcriptionQueue.progress[episodeID] ?? 0
      Self.log.info(
        """
        transcriptionTelemetry event=episodeCancelled \(logContext.fields) \
        wallSeconds=\((continuousClockNow() - startedAt).asTimeInterval) \
        liveProgress=\(liveProgress)
        """
      )
      transcriptionQueue.clearProgress(for: episodeID)
      throw CancellationError()
    } catch {
      let liveProgress = transcriptionQueue.progress[episodeID] ?? 0
      Self.log.caughtError(
        """
        transcriptionTelemetry event=episodeFailed \(logContext.fields) \
        wallSeconds=\((continuousClockNow() - startedAt).asTimeInterval) \
        liveProgress=\(liveProgress)
        """,
        error
      )
      transcriptionQueue.fail(episodeID)
      if transcriptionQueue.episodeIDs.isEmpty {
        backgroundTaskScheduler.scheduleNext()
      }
      return
    }

    Self.log.info(
      """
      transcriptionTelemetry event=episodeFinished \(logContext.fields) \
      wallSeconds=\((continuousClockNow() - startedAt).asTimeInterval) \
      remainingEpisodes=\(transcriptionQueue.episodeIDs.count)
      """
    )
    if transcriptionQueue.episodeIDs.isEmpty {
      backgroundTaskScheduler.scheduleNext()
    }
  }

  private func process(
    _ episodeID: Episode.ID,
    logContext: TranscriptionLogContext
  ) async throws {
    guard let episode = try await repo.episode(episodeID) else {
      transcriptionQueue.remove(episodeID)
      Self.log.warning("Removed missing \(episodeID) from transcription queue")
      return
    }
    guard !episode.hasTranscript else {
      try await repo.deleteTranscriptionCheckpoint(for: episodeID)
      transcriptionQueue.remove(episodeID)
      Self.log.debug("Removed already-transcribed \(episodeID) from transcription queue")
      return
    }

    let locale = TranscriptionAvailability.locale
    guard await transcriber.supports(locale) else {
      throw TranscriptionError.localeNotSupported(locale)
    }
    try Task.checkCancellation()

    let checkpoint: TranscriptionCheckpoint?
    do {
      checkpoint = try await repo.transcriptionCheckpoint(episodeID)
    } catch {
      Self.log.caughtError("Discarding unreadable transcription checkpoint for \(episodeID)", error)
      try await repo.deleteTranscriptionCheckpoint(for: episodeID)
      checkpoint = nil
    }

    let localeIdentifier = locale.identifier(.bcp47)
    let initialProgress: Double
    if let checkpoint,
      checkpoint.locale == localeIdentifier
    {
      initialProgress = checkpoint.progress
    } else {
      initialProgress = 0
    }
    transcriptionQueue.setProgress(initialProgress, for: episodeID)
    let checkpointState = checkpoint == nil ? "absent" : "present"
    Self.log.info(
      """
      transcriptionTelemetry event=checkpointLoaded \(logContext.fields) \
      checkpointState=\(checkpointState) progress=\(initialProgress) \
      committedAudioSeconds=\(checkpoint?.audioTime ?? 0) \
      checkpointSegments=\(checkpoint?.segments.count ?? 0)
      """
    )

    guard let cachedURL = try await cacheManager.cachedURL(downloadingIfNeeded: episodeID) else {
      throw TranscriptionError.audioUnavailable(episodeID)
    }
    Self.log.debug(
      """
      transcriptionTelemetry event=audioReady \(logContext.fields) \
      file=\(cachedURL.rawValue.lastPathComponent)
      """
    )

    let queue = transcriptionQueue
    let repo = repo
    let clockNow = continuousClockNow
    let segments = try await transcriber.transcribe(
      fileURL: cachedURL.rawValue,
      locale: locale,
      logContext: logContext,
      checkpoint: checkpoint,
      onProgress: { queue.setProgress($0, for: episodeID) },
      onCheckpoint: { checkpoint in
        let writeStartedAt = clockNow()
        try await repo.saveTranscriptionCheckpoint(checkpoint, for: episodeID)
        queue.setProgress(checkpoint.progress, for: episodeID)
        Self.log.debug(
          """
          transcriptionTelemetry event=checkpointPersisted \(logContext.fields) \
          committedAudioSeconds=\(checkpoint.audioTime) \
          durationSeconds=\(checkpoint.duration) progress=\(checkpoint.progress) \
          segments=\(checkpoint.segments.count) \
          writeWallSeconds=\((clockNow() - writeStartedAt).asTimeInterval)
          """
        )
      }
    )
    let transcript = Transcript(
      segments: segments,
      locale: localeIdentifier,
      createdAt: Date()
    )
    try await repo.updateTranscript(episodeID, transcript: transcript.jsonString())

    transcriptionQueue.remove(episodeID)
    Self.log.info(
      """
      transcriptionTelemetry event=transcriptStored \(logContext.fields) \
      segments=\(segments.count)
      """
    )
  }
}
