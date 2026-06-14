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
// background too. Either path is resumable: the persisted queue survives
// cancellation/expiry, and the next activation or grant picks up the head.
struct TranscriptionProcessor: Sendable {
  @DynamicInjected(\.cacheManager) private var cacheManager
  @DynamicInjected(\.repo) private var repo
  @DynamicInjected(\.taskPriority) private var taskPriority
  @DynamicInjected(\.transcriber) private var transcriber
  @DynamicInjected(\.transcriptionQueue) private var transcriptionQueue

  private static let log = Log.as(LogSubsystem.Transcription.processor)
  private static let locale = Locale(identifier: "en-US")

  private static let backgroundTaskIdentifier = "\(AppInfo.bundleIdentifier).transcription"

  private let backgroundTaskScheduler: BackgroundTaskScheduler
  private let processingTask = ThreadSafe<Task<Void, Never>?>(nil)

  fileprivate init() {
    backgroundTaskScheduler = BackgroundTaskScheduler(
      identifier: Self.backgroundTaskIdentifier,
      cadence: .minutes(1),
      taskType: .processing(requiresNetworkConnectivity: false)
    )
  }

  // MARK: - Background Task

  // iOS-granted background drain, mirroring EmbeddingProcessor: discretionary
  // and resumable. The persisted queue survives expiry, so the next grant or
  // foreground activation continues from wherever this left off.
  func register() {
    backgroundTaskScheduler.register { complete in
      Self.log.info("Starting transcription background task")
      do {
        try await drainUntilEmpty()
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
      start()
    case .background:
      Self.log.debug("backgrounded")
      stop()
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
        await drain()
      }
    }
  }

  private func stop() {
    processingTask { task in
      task?.cancel()
      task = nil
    }
  }

  // Foreground drain: every queue change wakes a drain of the head down to
  // empty. The stream replays the current queue on subscription and ends on
  // task cancellation, so a backgrounded processor falls out of the loop
  // cleanly and the persisted queue resumes on the next activation.
  private func drain() async {
    for await _ in transcriptionQueue.$episodeIDs.stream() {
      do {
        try await drainUntilEmpty()
      } catch {
        return  // Cancelled — the queue resumes on the next activation.
      }
    }
  }

  // Process the head episode until the queue empties, or until expiry surfaces
  // as cancellation (rethrown so callers stop). Shared by the foreground drain
  // and the background task.
  private func drainUntilEmpty() async throws {
    while let episodeID = transcriptionQueue.episodeIDs.first {
      try Task.checkCancellation()
      try await processHead(episodeID)
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
  }

  private func process(_ episodeID: Episode.ID) async throws {
    guard let episode = try await repo.episode(episodeID) else {
      transcriptionQueue.remove(episodeID)
      return
    }
    guard !episode.hasTranscript else {
      transcriptionQueue.remove(episodeID)
      return
    }

    transcriptionQueue.setProgress(0, for: episodeID)
    Self.log.info("Transcribing \(episodeID)")

    guard let cachedURL = try await cacheManager.cachedURL(downloadingIfNeeded: episodeID) else {
      throw TranscriptionError.audioUnavailable(episodeID)
    }
    let queue = transcriptionQueue
    let segments = try await transcriber.transcribe(
      fileURL: cachedURL.rawValue,
      locale: Self.locale,
      onProgress: { queue.setProgress($0, for: episodeID) }
    )
    let transcript = Transcript(
      segments: segments,
      locale: Self.locale.identifier(.bcp47),
      createdAt: Date(),
      modelRevision: Transcriber.recipeVersion
    )
    try await repo.updateTranscript(episodeID, transcript: transcript.jsonString())

    transcriptionQueue.clearProgress(for: episodeID)
    transcriptionQueue.remove(episodeID)
    Self.log.info("Transcribed \(episodeID): \(segments.count) segments")
  }
}
