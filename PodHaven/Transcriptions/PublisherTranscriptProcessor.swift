// Copyright Justin Bishop, 2026

import FactoryKit
import Foundation
import Logging
import SwiftUI

extension Container {
  var publisherTranscriptProcessor: Factory<PublisherTranscriptProcessor> {
    Factory(self) { PublisherTranscriptProcessor() }.scope(.cached)
  }
}

struct PublisherTranscriptProcessor: Sendable {
  @DynamicInjected(\.dateProvider) private var dateProvider
  @DynamicInjected(\.publisherTranscriptImporter) private var importer
  @DynamicInjected(\.publisherTranscriptImportStore) private var store
  @DynamicInjected(\.repo) private var repo
  @DynamicInjected(\.taskPriority) private var taskPriority
  @DynamicInjected(\.transcriptionProcessor) private var transcriptionProcessor

  private static let backgroundTaskIdentifier =
    "\(AppInfo.bundleIdentifier).publisherTranscripts"
  private static let batchSize = 20
  private static let log = Log.as(LogSubsystem.Transcription.processor)

  private enum LifecycleState: Sendable {
    case foreground
    case background
  }

  private struct ForegroundDrain: Sendable {
    let token: UUID
    let task: Task<Void, Never>
  }

  private struct DrainSummary: Sendable {
    let hasEligibleWork: Bool
  }

  private let backgroundTaskScheduler: BackgroundTaskScheduler
  private let drainLock = ThreadLock()
  private let foregroundDrain = ThreadSafe<ForegroundDrain?>(nil)
  private let hasWork: ThreadSafe<Bool>
  private let lifecycleState = ThreadSafe(LifecycleState.background)
  private let workGeneration = ThreadSafe(0)

  fileprivate init() {
    let hasWork = ThreadSafe(true)
    self.hasWork = hasWork
    backgroundTaskScheduler = BackgroundTaskScheduler(
      identifier: Self.backgroundTaskIdentifier,
      cadence: .minutes(1),
      taskType: .processing(requiresNetworkConnectivity: true),
      schedulingMode: .onDemand { hasWork() },
      expirationBehavior: .awaitCancellation
    )
  }

  func register() {
    let processor = self
    backgroundTaskScheduler.register { complete in
      do {
        _ = try await processor.drainAvailableWork()
        complete(true)
      } catch is CancellationError {
        Self.log.info("Publisher transcript background task expired")
        complete(false)
      } catch {
        Self.log.caughtError("Publisher transcript background task failed", error)
        complete(false)
      }
    }

    Task(priority: taskPriority(.background)) {
      await processor.reconcilePersistedWork()
    }
  }

  func handleScenePhaseChange(to scenePhase: ScenePhase) {
    switch scenePhase {
    case .active:
      lifecycleState(.foreground)
      startForegroundDrain()
    case .background:
      lifecycleState(.background)
      stopForegroundDrain()
      backgroundTaskScheduler.scheduleNext()
    default:
      break
    }
  }

  func workBecameAvailable() {
    workGeneration { $0 += 1 }
    hasWork(true)
    switch lifecycleState() {
    case .foreground:
      startForegroundDrain()
    case .background:
      backgroundTaskScheduler.scheduleNext()
    }
  }

  func makeForegroundProgress() async {
    do {
      _ = try await drainAvailableWork()
    } catch is CancellationError {
      return
    } catch {
      Self.log.caughtError("Foreground publisher transcript drain failed", error)
    }
  }

  private func startForegroundDrain() {
    let token = UUID()
    let generation = workGeneration()
    let startLatch = AsyncLatch<Void>()
    let processor = self
    let task = Task(priority: taskPriority(.background)) {
      do {
        try await startLatch.wait()
        let summary = try await processor.drainAvailableWork()
        processor.foregroundDrainFinished(
          token: token,
          shouldContinue: summary.hasEligibleWork
            || processor.workGeneration() != generation
        )
      } catch is CancellationError {
        processor.foregroundDrainFinished(token: token, shouldContinue: false)
      } catch {
        Self.log.caughtError("Foreground publisher transcript drain failed", error)
        processor.foregroundDrainFinished(token: token, shouldContinue: false)
      }
    }
    let shouldStart = foregroundDrain { current in
      guard current == nil else { return false }
      current = ForegroundDrain(token: token, task: task)
      return true
    }
    if !shouldStart {
      task.cancel()
    }
    startLatch.open()
  }

  private func stopForegroundDrain() {
    let task = foregroundDrain { current -> Task<Void, Never>? in
      let task = current?.task
      current = nil
      return task
    }
    task?.cancel()
  }

  private func foregroundDrainFinished(token: UUID, shouldContinue: Bool) {
    let cleared = foregroundDrain { current in
      guard current?.token == token else { return false }
      current = nil
      return true
    }
    if cleared, shouldContinue, case .foreground = lifecycleState() {
      startForegroundDrain()
    }
  }

  private func reconcilePersistedWork() async {
    do {
      hasWork(try await store.hasWork())
    } catch {
      hasWork(true)
      Self.log.caughtError("Failed to reconcile publisher transcript work", error)
    }
    backgroundTaskScheduler.scheduleNext()
  }

  private func drainAvailableWork() async throws -> DrainSummary {
    try await drainLock.waitForClaim()
    defer { drainLock.release() }

    let jobs = try await store.eligibleJobs(
      at: dateProvider.now,
      limit: Self.batchSize
    )
    for job in jobs {
      try Task.checkCancellation()
      try await process(job)
    }

    try Task.checkCancellation()
    let now = dateProvider.now
    let hasEligibleWork = try await store.hasEligibleWork(at: now)
    hasWork(try await store.hasWork())
    backgroundTaskScheduler.scheduleNext()
    return DrainSummary(hasEligibleWork: hasEligibleWork)
  }

  private func process(_ job: PublisherTranscriptImportJob) async throws {
    guard let episode = try await repo.episode(job.episodeId) else {
      try await store.remove(job.episodeId)
      return
    }
    guard !episode.hasTranscript else {
      try await store.remove(job.episodeId)
      return
    }

    let expectedReferences = episode.publisherTranscriptReferences
    switch try await importer.attemptImport(
      from: expectedReferences
    ) {
    case .imported(let imported):
      let stored = try await transcriptionProcessor.storePublisherTranscript(
        imported,
        for: episode.id,
        expectedReferences: expectedReferences
      )
      Self.log.info(
        "Publisher transcript demand resolved for episode \(episode.id) stored=\(stored)"
      )
    case .terminalFailure:
      let removed = try await store.remove(
        job,
        ifReferencesMatch: expectedReferences
      )
      Self.log.info(
        "Terminal publisher transcript outcome for episode \(episode.id) removed=\(removed)"
      )
    case .retryableFailure:
      let result = try await store.recordRetry(
        for: job,
        at: dateProvider.now,
        ifReferencesMatch: expectedReferences
      )
      switch result {
      case .exhausted(let attemptCount):
        Self.log.info(
          "Publisher transcript retry exhausted for episode \(episode.id) attempt=\(attemptCount)"
        )
      case .resolved:
        Self.log.info("Publisher transcript retry already resolved for episode \(episode.id)")
      case .retained(let attemptCount):
        Self.log.info(
          "Publisher transcript retry retained for episode \(episode.id) attempt=\(attemptCount)"
        )
      case .superseded:
        Self.log.info("Publisher transcript retry superseded for episode \(episode.id)")
      }
    }
  }
}
