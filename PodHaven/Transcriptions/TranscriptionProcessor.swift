// Copyright Justin Bishop, 2026

import AVFoundation
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

struct TranscriptionProcessor: Sendable {
  @DynamicInjected(\.cacheManager) private var cacheManager
  @DynamicInjected(\.continuousClockNow) private var continuousClockNow
  @DynamicInjected(\.notificationObserver) private var notificationObserver
  @DynamicInjected(\.publisherTranscriptImporter) private var publisherTranscriptImporter
  @DynamicInjected(\.repo) private var repo
  @DynamicInjected(\.taskPriority) private var taskPriority
  @DynamicInjected(\.transcriber) private var transcriber
  @DynamicInjected(\.transcriptionQueue) private var transcriptionQueue

  private static let log = Log.as(LogSubsystem.Transcription.processor)

  private static let backgroundTaskIdentifier = "\(AppInfo.bundleIdentifier).transcription"

  private let backgroundTaskScheduler: BackgroundTaskScheduler
  private let processingTask = ThreadSafe<Task<Void, Never>?>(nil)

  private struct ActiveTranscription: Sendable {
    enum Interruption: Sendable {
      case none
      case pause
      case discard
      case requeue
      case deletion(AsyncLatch<Void>)
      case mediaServicesReset
      case publisherTranscript
      case replacementRequest

      var isNone: Bool {
        if case .none = self { return true }
        return false
      }
    }

    let token: UUID
    let episodeID: Episode.ID
    let workMode: TranscriptionWorkMode
    let task: Task<Void, any Error>
    var interruption = Interruption.none
  }

  private enum MediaServicesState: Sendable {
    case available
    case lost(AsyncLatch<Void>)
  }

  private let activeTranscription = ThreadSafe<ActiveTranscription?>(nil)
  private let deletionBarrier = ThreadSafe<AsyncLatch<Void>?>(nil)
  private let deletionLock = ThreadLock()
  private let mediaServicesState = ThreadSafe(MediaServicesState.available)

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

  func register() {
    let activeTranscription = activeTranscription
    let mediaServicesState = mediaServicesState
    let interruptActiveTranscription:
      @Sendable () -> (episodeID: Episode.ID, task: Task<Void, any Error>)? =
        {
          activeTranscription {
            active -> (episodeID: Episode.ID, task: Task<Void, any Error>)? in
            guard var current = active, current.interruption.isNone else {
              return nil
            }
            current.interruption = .mediaServicesReset
            active = current
            return (current.episodeID, current.task)
          }
        }

    notificationObserver.observe(
      AVAudioSession.mediaServicesWereLostNotification
    ) {
      mediaServicesState { state in
        guard case .available = state else { return }
        state = .lost(AsyncLatch<Void>())
      }
      guard let interruption = interruptActiveTranscription() else { return }
      Self.log.notice(
        "Retaining active transcription \(interruption.episodeID) while media services restart"
      )
      interruption.task.cancel()
    }

    notificationObserver.observe(
      AVAudioSession.mediaServicesWereResetNotification
    ) {
      let resumeLatch = mediaServicesState { state -> AsyncLatch<Void>? in
        guard case .lost(let latch) = state else { return nil }
        state = .available
        return latch
      }
      if let resumeLatch {
        Self.log.notice("Media services reset; resuming retained transcription work")
        resumeLatch.open()
      }

      let reset = interruptActiveTranscription()
      guard let reset else { return }
      Self.log.notice(
        "Rebuilding active transcription \(reset.episodeID) after media services reset"
      )
      reset.task.cancel()
    }

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

    let queue = transcriptionQueue
    let scheduler = backgroundTaskScheduler
    Task {
      await queue.waitUntilLoaded()
      scheduler.scheduleNext()
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

  // MARK: - Queue Mutations

  func enqueue(_ episodeID: Episode.ID) async throws {
    try await enqueue([episodeID])
  }

  func enqueue(_ episodeIDs: [Episode.ID]) async throws {
    try await transcriptionQueue.enqueue(episodeIDs)
    backgroundTaskScheduler.scheduleNext()
  }

  func enqueuePublisherReplacement(_ episodeID: Episode.ID) async throws {
    try await transcriptionQueue.enqueueReplacement(episodeID)
    let activeTask = activeTranscription { active -> Task<Void, any Error>? in
      guard
        var current = active,
        current.episodeID == episodeID,
        current.workMode != .onDeviceReplacement,
        current.interruption.isNone
      else {
        return nil
      }
      current.interruption = .replacementRequest
      active = current
      return current.task
    }
    activeTask?.cancel()
    backgroundTaskScheduler.scheduleNext()
  }

  @discardableResult
  func importPublisherTranscript(for episodeID: Episode.ID) async -> Bool {
    do {
      guard
        let episode = try await repo.episode(episodeID),
        !episode.hasTranscript,
        transcriptionQueue.work(for: episodeID)?.mode != .onDeviceReplacement,
        try await publisherTranscriptImporter.importAndStoreIfAbsent(
          for: episode,
          in: repo
        )
      else {
        return false
      }

      let activeTask = activeTranscription { active -> Task<Void, any Error>? in
        guard
          var current = active,
          current.episodeID == episodeID,
          current.workMode == .publisherPreferred,
          current.interruption.isNone
        else {
          return nil
        }
        current.interruption = .publisherTranscript
        active = current
        return current.task
      }
      if let activeTask {
        Self.log.info("Cancelling redundant on-device transcription \(episodeID)")
        activeTask.cancel()
        switch await activeTask.result {
        case .success, .failure:
          break
        }
      }

      do {
        let removedPublisherWork = try await transcriptionQueue.remove(
          episodeID,
          ifMode: .publisherPreferred
        )
        if removedPublisherWork {
          try await repo.deleteTranscriptionCheckpoint(for: episodeID)
        } else {
          Self.log.debug(
            "Preserved newer transcription work after publisher import \(episodeID)"
          )
        }
      } catch {
        Self.log.caughtError(
          "Failed to reconcile publisher-transcribed episode \(episodeID)",
          error
        )
        backgroundTaskScheduler.scheduleNext()
      }
      if transcriptionQueue.episodeIDs.isEmpty {
        backgroundTaskScheduler.scheduleNext()
      }
      Self.log.info("Stored publisher transcript for episode \(episodeID)")
      return true
    } catch is CancellationError {
      return false
    } catch {
      Self.log.caughtError(
        "Failed to import publisher transcript for episode \(episodeID)",
        error,
        level: .info
      )
      return false
    }
  }

  func reconcileDeletion<Result: Sendable>(
    resolvingEpisodeIDs: () async throws -> Set<Episode.ID>,
    perform deletion: () async throws -> Result
  ) async throws -> Result {
    try await deletionLock.waitForClaim()
    defer { deletionLock.release() }

    let barrier = AsyncLatch<Void>()
    deletionBarrier(barrier)
    defer {
      barrier.open()
      deletionBarrier { current in
        if current === barrier {
          current = nil
        }
      }
    }

    let result = try await transcriptionQueue.reconcileDeletion(
      resolvingEpisodeIDs: resolvingEpisodeIDs,
      prepare: { deletingEpisodeIDs in
        let activeTask = activeTranscription {
          active -> (episodeID: Episode.ID, task: Task<Void, any Error>)? in
          guard var current = active, deletingEpisodeIDs.contains(current.episodeID) else {
            return nil
          }
          if current.interruption.isNone {
            current.interruption = .deletion(barrier)
            active = current
          }
          return (episodeID: current.episodeID, task: current.task)
        }
        guard let activeTask else { return }

        Self.log.info("Requested deletion of active transcription \(activeTask.episodeID)")
        activeTask.task.cancel()
        switch await activeTask.task.result {
        case .success, .failure:
          break
        }
      },
      perform: deletion
    )
    if transcriptionQueue.episodeIDs.isEmpty {
      backgroundTaskScheduler.scheduleNext()
    }
    return result
  }

  // MARK: - User Interruption

  func pause(_ episodeID: Episode.ID) async throws {
    guard try await transcriptionQueue.beginPausing(episodeID) else { return }

    let activeTask = activeTranscription { active -> Task<Void, any Error>? in
      guard var current = active, current.episodeID == episodeID else {
        return nil
      }
      guard current.interruption.isNone else { return nil }
      current.interruption = .pause
      active = current
      return current.task
    }

    if let activeTask {
      Self.log.info("Requested pause of active transcription \(episodeID)")
      activeTask.cancel()
    } else {
      transcriptionQueue.finishPausing(episodeID)
      Self.log.info(
        """
        Removed waiting transcription \(episodeID); \
        remainingEpisodes=\(transcriptionQueue.episodeIDs.count)
        """
      )
    }

    if transcriptionQueue.episodeIDs.isEmpty {
      backgroundTaskScheduler.scheduleNext()
    }
  }

  func discardProgress(for episodeID: Episode.ID) async throws {
    guard try await transcriptionQueue.beginDiscarding(episodeID) else {
      return
    }

    let activeTask = activeTranscription { active -> Task<Void, any Error>? in
      guard var current = active, current.episodeID == episodeID else {
        return nil
      }
      current.interruption = .discard
      active = current
      return current.task
    }

    if let activeTask {
      Self.log.info(
        "Requested progress discard for active transcription \(episodeID)"
      )
      activeTask.cancel()
    } else {
      Self.log.info("Requested saved transcription progress discard \(episodeID)")
      await Self.deleteCheckpoint(for: episodeID, using: repo)
      transcriptionQueue.finishDiscarding(episodeID)
    }

    if transcriptionQueue.episodeIDs.isEmpty {
      backgroundTaskScheduler.scheduleNext()
    }
  }

  // MARK: - User Reordering

  @discardableResult
  func reorder(_ orderedEpisodeIDs: [Episode.ID]) async throws -> Bool {
    guard try await transcriptionQueue.reorder(orderedEpisodeIDs) else {
      return false
    }

    let activeTask = activeTranscription { active -> Task<Void, any Error>? in
      guard
        var current = active,
        current.interruption.isNone,
        orderedEpisodeIDs.first != current.episodeID
      else {
        return nil
      }
      current.interruption = .requeue
      active = current
      return current.task
    }

    if let activeTask {
      Self.log.info("Pausing active transcription after queue reorder")
      activeTask.cancel()
    }
    return true
  }

  private static func deleteCheckpoint(
    for episodeID: Episode.ID,
    using repo: any Databasing
  ) async {
    do {
      try await repo.deleteTranscriptionCheckpoint(for: episodeID)
    } catch {
      Self.log.caughtError(
        "Failed to delete transcription checkpoint for \(episodeID)",
        error
      )
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

  private func drain(_ mode: TranscriptionLogContext.Mode, runID: String) async throws {
    try await transcriptionQueue.withWorkStream { stream in
      if case .background = mode, transcriptionQueue.episodeIDs.isEmpty {
        return
      }

      for await episodeID in stream {
        processingHead: while true {
          try Task.checkCancellation()
          if case .foreground = mode, case .background = foregroundState() {
            return
          }
          if case .lost(let resumeLatch) = mediaServicesState() {
            try await resumeLatch.wait()
            try Task.checkCancellation()
            if case .foreground = mode, case .background = foregroundState() {
              return
            }
          }
          let outcome = try await processHead(
            episodeID,
            logContext: TranscriptionLogContext(
              runID: runID,
              mode: mode,
              episodeID: episodeID
            )
          )
          switch outcome {
          case .restart:
            guard transcriptionQueue.episodeIDs.first == episodeID else {
              break processingHead
            }
            continue processingHead
          case .retained:
            if case .background = mode {
              return
            }
            break processingHead
          case .advanced:
            break processingHead
          }
        }
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

  private func processHead(
    _ episodeID: Episode.ID,
    logContext: TranscriptionLogContext
  ) async throws -> HeadProcessingOutcome {
    if let barrier = deletionBarrier() {
      try await barrier.wait()
    }
    guard let work = transcriptionQueue.work(for: episodeID) else {
      return .advanced
    }

    let startedAt = continuousClockNow()
    let startLatch = AsyncLatch<Void>()
    let task = Task {
      try await startLatch.wait()
      try Task.checkCancellation()
      try await process(work, logContext: logContext)
    }
    let token = UUID()
    let shouldStart = activeTranscription { active in
      guard
        transcriptionQueue.episodeIDs.first == episodeID,
        transcriptionQueue.work(for: episodeID) == work
      else { return false }
      guard case .available = mediaServicesState() else { return false }
      if let active {
        Assert.fatal(
          """
          Cannot start transcription \(episodeID) while \(active.episodeID) is active
          """
        )
      }
      active = ActiveTranscription(
        token: token,
        episodeID: episodeID,
        workMode: work.mode,
        task: task
      )
      return true
    }
    guard shouldStart else {
      task.cancel()
      startLatch.open()
      do {
        try await task.value
      } catch is CancellationError {
        try Task.checkCancellation()
      } catch {
        Self.log.caughtError("Discarded stale transcription task for \(episodeID)", error)
      }
      return transcriptionQueue.episodeIDs.first == episodeID
        ? .restart
        : .advanced
    }

    Self.log.info(
      """
      transcriptionTelemetry event=episodeStarted \(logContext.fields) \
      queuedEpisodes=\(transcriptionQueue.episodeIDs.count)
      """
    )
    startLatch.open()
    do {
      try await withTaskCancellationHandler {
        try await task.value
        try Task.checkCancellation()
      } onCancel: {
        task.cancel()
      }
    } catch {
      let errorIsCancellation = error is CancellationError
      let result = activeTranscription { active in
        guard let current = active, current.token == token else {
          Assert.fatal("Lost ownership of active transcription \(episodeID)")
        }
        let interruption: ActiveTranscription.Interruption
        if current.interruption.isNone,
          case .lost = mediaServicesState()
        {
          interruption = .mediaServicesReset
        } else {
          interruption = current.interruption
        }
        let executionCancelled = errorIsCancellation || Task.isCancelled
        let liveProgress = transcriptionQueue.progress[episodeID] ?? 0
        active = nil
        return (
          interruption: interruption,
          executionCancelled: executionCancelled,
          liveProgress: liveProgress
        )
      }

      if let queueMutationFailure = error as? QueueMutationFailure {
        Self.log.caughtError(
          """
          transcriptionTelemetry event=queueMutationFailed \(logContext.fields) \
          operation=\(queueMutationFailure.operation.rawValue) \
          remainingEpisodes=\(transcriptionQueue.episodeIDs.count)
          """,
          queueMutationFailure
        )
        if result.interruption.isNone {
          transcriptionQueue.clearProgress(for: episodeID)
          backgroundTaskScheduler.scheduleNext()
          return .retained
        }
      }
      if error is TranscriptionWorkModeChanged, result.interruption.isNone {
        transcriptionQueue.clearProgress(for: episodeID)
        return .restart
      }

      if result.interruption.isNone, !result.executionCancelled {
        Self.log.caughtError(
          """
          transcriptionTelemetry event=episodeFailed \(logContext.fields) \
          wallSeconds=\((continuousClockNow() - startedAt).asTimeInterval) \
          liveProgress=\(result.liveProgress)
          """,
          error
        )
        do {
          guard try await transcriptionQueue.fail(episodeID, ifMode: work.mode)
          else {
            transcriptionQueue.clearProgress(for: episodeID)
            return .restart
          }
        } catch is CancellationError {
          throw CancellationError()
        } catch {
          Self.log.caughtError(
            "Failed to persist failed transcription \(episodeID); retained queued work",
            error
          )
          transcriptionQueue.clearProgress(for: episodeID)
          backgroundTaskScheduler.scheduleNext()
          return .retained
        }
        if transcriptionQueue.episodeIDs.isEmpty {
          backgroundTaskScheduler.scheduleNext()
        }
        return .advanced
      }

      switch result.interruption {
      case .pause:
        transcriptionQueue.finishPausing(episodeID)
      case .discard, .requeue, .mediaServicesReset, .publisherTranscript,
        .replacementRequest, .none:
        transcriptionQueue.clearProgress(for: episodeID)
      case .deletion(let barrier):
        try await barrier.wait()
      }

      if !result.interruption.isNone || result.executionCancelled {
        let source =
          switch result.interruption {
          case .pause: "pause"
          case .discard: "discard"
          case .requeue: "requeue"
          case .deletion: "deletion"
          case .mediaServicesReset: "mediaServicesReset"
          case .publisherTranscript: "publisherTranscript"
          case .replacementRequest: "replacementRequest"
          case .none: "execution"
          }
        Self.log.info(
          """
          transcriptionTelemetry event=episodeCancelled \(logContext.fields) \
          cancellationSource=\(source) \
          wallSeconds=\((continuousClockNow() - startedAt).asTimeInterval) \
          liveProgress=\(result.liveProgress)
          """
        )
        if case .discard = result.interruption {
          await Self.deleteCheckpoint(for: episodeID, using: repo)
          transcriptionQueue.finishDiscarding(episodeID)
        }
        if transcriptionQueue.episodeIDs.isEmpty {
          backgroundTaskScheduler.scheduleNext()
        }
        if Task.isCancelled || result.interruption.isNone {
          throw CancellationError()
        }
        if case .mediaServicesReset = result.interruption {
          return .restart
        }
        if case .replacementRequest = result.interruption {
          return .restart
        }
        return .advanced
      }
    }

    let completionInterruption = activeTranscription { active in
      guard let current = active, current.token == token else {
        Assert.fatal("Lost ownership of completed transcription \(episodeID)")
      }
      active = nil
      return current.interruption
    }
    switch completionInterruption {
    case .pause:
      transcriptionQueue.finishPausing(episodeID)
    case .discard:
      transcriptionQueue.finishDiscarding(episodeID)
    case .requeue:
      transcriptionQueue.clearProgress(for: episodeID)
    case .deletion(let barrier):
      try await barrier.wait()
    case .mediaServicesReset:
      transcriptionQueue.clearProgress(for: episodeID)
    case .publisherTranscript:
      transcriptionQueue.clearProgress(for: episodeID)
    case .replacementRequest:
      transcriptionQueue.clearProgress(for: episodeID)
    case .none:
      break
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
    return .advanced
  }

  private func process(
    _ work: TranscriptionWork,
    logContext: TranscriptionLogContext
  ) async throws {
    let episodeID = work.episodeID
    guard let episode = try await repo.episode(episodeID) else {
      try await removeQueuedEpisode(
        work,
        operation: .missingEpisode
      )
      Self.log.warning("Removed missing \(episodeID) from transcription queue")
      return
    }

    if work.mode == .publisherPreferred, episode.hasTranscript {
      try await repo.deleteTranscriptionCheckpoint(for: episodeID)
      try await removeQueuedEpisode(
        work,
        operation: .alreadyTranscribed
      )
      Self.log.debug("Removed already-transcribed \(episodeID) from transcription queue")
      return
    }
    if work.mode == .onDeviceReplacement,
      episode.hasTranscript,
      episode.publisherTranscriptSource == nil
    {
      try await repo.deleteTranscriptionCheckpoint(for: episodeID)
      guard
        try await transcriptionQueue.reconcilePublisherReplacement(work)
      else { throw TranscriptionWorkModeChanged() }
      Self.log.debug("Removed obsolete replacement work for \(episodeID)")
      return
    }

    if work.mode == .publisherPreferred,
      try await publisherTranscriptImporter.importAndStoreIfAbsent(
        for: episode,
        in: repo
      )
    {
      try await removeQueuedEpisode(
        work,
        operation: .publisherTranscript
      )
      Self.log.info("Stored publisher transcript for queued episode \(episodeID)")
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
    try Task.checkCancellation()
    let stored: Bool
    switch work.mode {
    case .publisherPreferred:
      stored = try await repo.storeTranscriptIfAbsent(
        episodeID,
        transcript: transcript,
        publisherSource: nil
      )
      if !stored {
        try await repo.deleteTranscriptionCheckpoint(for: episodeID)
      }
      try await removeQueuedEpisode(
        work,
        operation: .completedTranscription
      )
    case .onDeviceReplacement:
      switch try await repo.replacePublisherTranscript(
        episodeID,
        with: transcript
      ) {
      case .replaced:
        guard
          try await transcriptionQueue.reconcilePublisherReplacement(work)
        else {
          throw TranscriptionWorkModeChanged()
        }
        stored = true
      case .publisherTranscriptUnavailable:
        stored = try await repo.storeTranscriptIfAbsent(
          episodeID,
          transcript: transcript,
          publisherSource: nil
        )
        if !stored {
          try await repo.deleteTranscriptionCheckpoint(for: episodeID)
        }
        try await removeQueuedEpisode(
          work,
          operation: .completedTranscription
        )
      case .workModeChanged:
        throw TranscriptionWorkModeChanged()
      }
    }
    Self.log.info(
      """
      transcriptionTelemetry event=transcriptStored \(logContext.fields) \
      segments=\(segments.count) stored=\(stored)
      """
    )
  }

  private func removeQueuedEpisode(
    _ work: TranscriptionWork,
    operation: QueueRemovalOperation
  ) async throws {
    let removed: Bool
    do {
      removed = try await transcriptionQueue.remove(
        work.episodeID,
        ifMode: work.mode
      )
    } catch is CancellationError {
      throw CancellationError()
    } catch {
      throw QueueMutationFailure(
        operation: operation,
        message: ErrorKit.message(for: error)
      )
    }
    guard removed else { throw TranscriptionWorkModeChanged() }
  }
}
