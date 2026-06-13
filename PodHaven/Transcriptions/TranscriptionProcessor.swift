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
  @DynamicInjected(\.sleeper) private var sleeper
  @DynamicInjected(\.taskPriority) private var taskPriority
  @DynamicInjected(\.transcriber) private var transcriber
  @DynamicInjected(\.transcriptionQueue) private var transcriptionQueue

  private static let log = Log.as(LogSubsystem.Transcription.processor)
  private static let locale = Locale(identifier: "en-US")
  // Bounded wait for an uncached episode's audio to finish downloading.
  private static let downloadPollInterval: Duration = .seconds(2)
  private static let maxDownloadPolls = 150

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

  private func drain() async {
    while !Task.isCancelled {
      guard let episodeID = transcriptionQueue.episodeIDs.first else {
        await waitForWork()
        continue
      }

      do {
        try await processHead(episodeID)
      } catch {
        return  // Cancelled — the foreground loop stops; the queue resumes later.
      }
    }
  }

  // Bounded drain for the background task: process until the queue empties, or
  // until expiry surfaces as cancellation (rethrown so register() completes).
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

  // Suspend until the queue next becomes non-empty. AsyncStream ends on task
  // cancellation, so a backgrounded processor falls out of the loop cleanly.
  private func waitForWork() async {
    for await ids in transcriptionQueue.$episodeIDs.stream() where !ids.isEmpty {
      return
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

    let fileURL = try await cachedAudioURL(for: episode)
    let segments = try await transcriber.transcribe(fileURL: fileURL, locale: Self.locale)
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

  private func cachedAudioURL(for episode: Episode) async throws -> URL {
    if let cachedURL = episode.cachedURL { return cachedURL.rawValue }

    Self.log.debug("Audio not cached for \(episode.id); downloading")
    try await cacheManager.downloadToCache(for: episode.id)

    for _ in 0..<Self.maxDownloadPolls {
      try Task.checkCancellation()
      if let cachedURL = try await repo.episode(episode.id)?.cachedURL {
        return cachedURL.rawValue
      }
      try await sleeper.sleep(for: Self.downloadPollInterval)
    }

    throw TranscriptionError.audioUnavailable(episode.id)
  }
}
