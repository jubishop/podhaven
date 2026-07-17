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
  @DynamicInjected(\.repo) private var repo
  @DynamicInjected(\.taskPriority) private var taskPriority
  @DynamicInjected(\.transcriber) private var transcriber
  @DynamicInjected(\.transcriptionQueue) private var transcriptionQueue

  private static let log = Log.as(LogSubsystem.Transcription.processor)

  private static let backgroundTaskIdentifier = "\(AppInfo.bundleIdentifier).transcription"

  private let backgroundTaskScheduler: BackgroundTaskScheduler
  private let processingTask = ThreadSafe<Task<Void, Never>?>(nil)

  private enum DrainMode {
    case foreground
    case background
  }

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
      schedulingMode: .onDemand { !queue.episodeIDs.isEmpty }
    )
  }

  // MARK: - Background Task

  // iOS-granted background drain, mirroring EmbeddingProcessor. The persisted
  // queue survives expiry, so the next grant or foreground activation retries
  // the retained head.
  func register() {
    backgroundTaskScheduler.register { complete in
      Self.log.info("Starting transcription background task")
      do {
        try await drain(.background)
        backgroundTaskScheduler.scheduleNext()
        Self.log.info("Transcription background task completed")
        complete(true)
      } catch is CancellationError {
        Self.log.info("Transcription background task cancelled (expired)")
        complete(false)
      } catch {
        Self.log.caughtError("Transcription background task failed", error)
        complete(false)
      }
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
          try await drain(.foreground)
        } catch is CancellationError {
          return
        } catch {
          Self.log.caughtError("Foreground transcription drain failed", error)
        }
      }
    }
  }

  private func stop() {
    processingTask { task in
      task?.cancel()
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
  private func drain(_ mode: DrainMode) async throws {
    try await transcriptionQueue.withWorkStream { stream in
      if case .background = mode, transcriptionQueue.episodeIDs.isEmpty {
        return
      }

      for await episodeID in stream {
        try Task.checkCancellation()
        if case .foreground = mode, case .background = foregroundState() {
          return
        }
        try await processHead(episodeID)
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
  private func processHead(_ episodeID: Episode.ID) async throws {
    do {
      try await process(episodeID)
    } catch is CancellationError {
      transcriptionQueue.clearProgress(for: episodeID)
      throw CancellationError()
    } catch {
      Self.log.caughtError("Transcription failed for \(episodeID)", error)
      transcriptionQueue.fail(episodeID)
    }

    if transcriptionQueue.episodeIDs.isEmpty {
      backgroundTaskScheduler.scheduleNext()
    }
  }

  private func process(_ episodeID: Episode.ID) async throws {
    guard let episode = try await repo.episode(episodeID) else {
      transcriptionQueue.remove(episodeID)
      Self.log.warning("Removed missing \(episodeID) from transcription queue")
      return
    }
    guard !episode.hasTranscript else {
      transcriptionQueue.remove(episodeID)
      Self.log.debug("Removed already-transcribed \(episodeID) from transcription queue")
      return
    }

    let locale = TranscriptionAvailability.locale
    guard await transcriber.supports(locale) else {
      throw TranscriptionError.localeNotSupported(locale)
    }

    transcriptionQueue.setProgress(0, for: episodeID)
    Self.log.info("Transcribing \(episodeID)")

    guard let cachedURL = try await cacheManager.cachedURL(downloadingIfNeeded: episodeID) else {
      throw TranscriptionError.audioUnavailable(episodeID)
    }
    let queue = transcriptionQueue
    let segments = try await transcriber.transcribe(
      fileURL: cachedURL.rawValue,
      locale: locale,
      onProgress: { queue.setProgress($0, for: episodeID) }
    )
    let transcript = Transcript(
      segments: segments,
      locale: locale.identifier(.bcp47),
      createdAt: Date(),
      modelRevision: Transcriber.recipeVersion
    )
    try await repo.updateTranscript(episodeID, transcript: transcript.jsonString())

    transcriptionQueue.remove(episodeID)
    Self.log.info("Transcribed \(episodeID): \(segments.count) segments")
  }
}
