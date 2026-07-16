// Copyright Justin Bishop, 2026

import BackgroundTasks
import FactoryKit
import Foundation
import GRDB
import Logging
import SwiftUI

// MARK: - Container

extension Container {
  var embeddingProcessor: Factory<EmbeddingProcessor> {
    Factory(self) { EmbeddingProcessor() }.scope(.cached)
  }
}

// MARK: - EmbeddingProcessor

struct EmbeddingProcessor: Sendable {
  @DynamicInjected(\.continuousClockNow) private var continuousClockNow
  @DynamicInjected(\.observatory) private var observatory
  @DynamicInjected(\.recommendationRepo) private var recommendationRepo
  @DynamicInjected(\.sleeper) private var sleeper
  @DynamicInjected(\.taskPriority) private var taskPriority

  private var contextualEmbedding: ContextualEmbedding {
    Container.shared.contextualEmbedding()
  }

  private static let log = Log.as(LogSubsystem.Recommendations.processor)

  private static let backgroundTaskIdentifier = "\(AppInfo.bundleIdentifier).embeddingComputation"

  private let backgroundTaskScheduler: BackgroundTaskScheduler
  private let foregroundTask = ThreadSafe<Task<Void, Never>?>(nil)
  private let registrationReconciliationOnce = Once()

  private enum ProcessingMode: Sendable {
    case foreground
    case background
  }

  private enum DrainResult {
    case empty(processedCount: Int)
    case pending(processedCount: Int)
  }

  private let processingMode = ThreadSafe(ProcessingMode.background)

  init() {
    backgroundTaskScheduler = BackgroundTaskScheduler(
      identifier: Self.backgroundTaskIdentifier,
      cadence: .minutes(1),
      taskType: .processing(requiresNetworkConnectivity: false),
      schedulingMode: .onDemand { Container.shared.embeddingWorkDemand().hasWork }
    )
  }

  // MARK: - Registration

  func register() {
    backgroundTaskScheduler.register { complete in
      Self.log.info("Starting embedding background task")

      await contextualEmbedding.loadAssetsIfAvailable()
      guard contextualEmbedding.assetsLoaded.isOpen else {
        Self.log.info("Contextual embedding assets not available yet, skipping")
        complete(true)
        return
      }

      do {
        let result = try await drainAvailableWork()
        switch result {
        case .empty(let processedCount):
          Self.log.info(
            "Embedding background task drained \(processedCount) episodes"
          )
        case .pending(let processedCount):
          Self.log.info(
            "Embedding background task processed \(processedCount) episodes with work remaining"
          )
        }
        complete(true)
      } catch is CancellationError {
        Self.log.info("Embedding background task cancelled (expired)")
        complete(false)
      } catch {
        Self.log.caughtError("Embedding background task failed", error)
        complete(false)
      }
    }

    registrationReconciliationOnce.run {
      Task(priority: taskPriority(.background)) {
        await reconcilePersistedDemand()
      }
    }
  }

  // MARK: - Scene Phase

  func handleScenePhaseChange(to scenePhase: ScenePhase) {
    switch scenePhase {
    case .active:
      Self.log.debug("activated")

      processingMode(.foreground)
      startForegroundObservation()
      if Container.shared.embeddingWorkDemand().hasWork {
        scheduleDrain()
      }
    case .background:
      Self.log.debug("backgrounded")

      processingMode(.background)
      stopForegroundObservation()
      backgroundTaskScheduler.scheduleNext()
    default:
      break
    }
  }

  func workBecameAvailable() {
    Container.shared.embeddingWorkDemand().markAvailable()

    switch processingMode() {
    case .foreground:
      scheduleDrain()
    case .background:
      backgroundTaskScheduler.scheduleNext()
    }
  }

  // MARK: - Foreground Observation

  // A feed refresh bumps `contentUpdatedAt` across a burst of episodes while
  // playback ticks write in parallel. `embeddingWorkSignal` ignores the
  // playback-path columns, and this debounce collapses each burst into a single
  // `episodesNeedingEmbeddings` scan once the writes settle — so the heavy
  // three-table join never runs per-commit on the database writer.
  //
  // The duration must stay larger than `contentUpdatedAt`'s timestamp
  // resolution: two content writes within one resolution tick share a MAX, so
  // the second's emission is dropped by the observation's `removeDuplicates`.
  // It is only ever picked up because it lands inside this debounce window of
  // the write that advanced MAX, so the pending drain still re-queries it.
  private let drainDebounce = Debounce(duration: .seconds(5), priority: .background)

  private func startForegroundObservation() {
    foregroundTask { task in
      guard task == nil else { return }
      task = Task(priority: taskPriority(.background)) {
        await contextualEmbedding.requestAndLoadAssetsIfNeeded()

        var retryDelay: Duration = .seconds(1)
        var hasReceivedEmission = false
        while !Task.isCancelled {
          do {
            for try await _ in observatory.embeddingWorkSignal() {
              guard !Task.isCancelled else { return }
              retryDelay = .seconds(1)
              if hasReceivedEmission {
                workBecameAvailable()
              } else {
                hasReceivedEmission = true
                scheduleDrain()
              }
            }
          } catch is CancellationError {
            return
          } catch {
            Self.log.caughtError("Foreground embedding observation failed", error)
            try? await sleeper.sleep(for: retryDelay)
            retryDelay = min(retryDelay * 2, .seconds(60))
          }
        }
      }
    }
  }

  private func scheduleDrain() {
    drainDebounce {
      do {
        try await contextualEmbedding.assetsLoaded.wait()
        try await drainAvailableWork()
      } catch is CancellationError {
        // Superseded by a newer trigger or backgrounded mid-drain; the next
        // foreground pass re-queries any remaining work.
      } catch {
        Self.log.caughtError("Foreground embedding drain failed", error)
      }
    }
  }

  private func stopForegroundObservation() {
    // Cancel the task before the debounce: a still-live task could arm a fresh
    // drain via `scheduleDrain`, and that debounce Task isn't a child of the
    // observation task. Cancelling the debounce last sweeps any such straggler.
    foregroundTask { task in
      task?.cancel()
      task = nil
    }
    drainDebounce.cancel()
  }

  private func reconcilePersistedDemand() async {
    let snapshot = Container.shared.embeddingWorkDemand().snapshot()
    do {
      let ids = try await episodeIDsNeedingWork(
        includeCurrent: snapshot.requiresFullRefresh
      )
      if ids.isEmpty {
        Container.shared.embeddingWorkDemand().clear(ifUnchanged: snapshot)
      } else {
        Container.shared.embeddingWorkDemand().ensureAvailable()
      }
    } catch {
      Container.shared.embeddingWorkDemand().ensureAvailable()
      Self.log.caughtError("Failed to reconcile persisted embedding demand", error)
    }
    backgroundTaskScheduler.scheduleNext()
  }

  @discardableResult
  private func drainAvailableWork() async throws -> DrainResult {
    let initialSnapshot = Container.shared.embeddingWorkDemand().snapshot()
    let ids = try await episodeIDsNeedingWork(
      includeCurrent: initialSnapshot.requiresFullRefresh
    )
    var batchResult = EmbeddingBatchResult(failedEpisodeCount: 0)

    if !ids.isEmpty {
      Container.shared.embeddingWorkDemand().ensureAvailable()
      Self.log.info("Processing \(ids.count) episodes for embeddings")
      batchResult = try await EmbeddingService.upsertEpisodeEmbeddings(
        forIDs: ids,
        embedding: contextualEmbedding
      )
    }

    try Task.checkCancellation()

    guard batchResult.failedEpisodeCount == 0 else {
      Container.shared.embeddingWorkDemand().ensureAvailable()
      return .pending(processedCount: ids.count)
    }

    let clearingSnapshot = Container.shared.embeddingWorkDemand().snapshot()
    let remaining = try await episodeIDsNeedingWork(includeCurrent: false)
    guard remaining.isEmpty else {
      Container.shared.embeddingWorkDemand().ensureAvailable()
      return .pending(processedCount: ids.count)
    }
    guard Container.shared.embeddingWorkDemand().clear(ifUnchanged: clearingSnapshot) else {
      return .pending(processedCount: ids.count)
    }

    backgroundTaskScheduler.scheduleNext()
    return .empty(processedCount: ids.count)
  }

  private func episodeIDsNeedingWork(includeCurrent: Bool) async throws -> [Episode.ID] {
    let queryStart = continuousClockNow()
    let ids = try await recommendationRepo.episodesNeedingEmbeddings(
      revision: contextualEmbedding.revision,
      includeCurrent: includeCurrent
    )
    let queryDuration = continuousClockNow() - queryStart
    Self.log.debug(
      "episodesNeedingEmbeddings query took \(queryDuration); found \(ids.count)"
    )
    return ids
  }
}
