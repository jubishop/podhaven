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

  init() {
    backgroundTaskScheduler = BackgroundTaskScheduler(
      identifier: Self.backgroundTaskIdentifier,
      cadence: .hours(1),
      taskType: .processing(requiresNetworkConnectivity: false)
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
        // IDs only — full Episode rows are hydrated in chunks during
        // processing so a BG-expiry doesn't waste a multi-second hydration
        // pass. Newest episodes (by pubDate) are ordered first.
        let queryStart = continuousClockNow()
        let idsToProcess = try await recommendationRepo.episodesNeedingEmbeddings(
          revision: contextualEmbedding.revision
        )
        let queryDuration = continuousClockNow() - queryStart
        Self.log.debug("episodesNeedingEmbeddings query took \(queryDuration)")

        if idsToProcess.isEmpty {
          Self.log.info("No episodes need embedding updates")
          complete(true)
          return
        }

        Self.log.info("Processing \(idsToProcess.count) episodes for embeddings")

        try await EmbeddingService.upsertEpisodeEmbeddings(
          forIDs: idsToProcess,
          embedding: contextualEmbedding
        )

        Self.log.info("Embedding background task completed successfully")
        complete(true)
      } catch is CancellationError {
        Self.log.info("Embedding background task cancelled (expired)")
        complete(false)
      } catch {
        Self.log.caughtError("Embedding background task failed", error)
        complete(false)
      }
    }
  }

  // MARK: - Scene Phase

  func handleScenePhaseChange(to scenePhase: ScenePhase) {
    switch scenePhase {
    case .active:
      Self.log.debug("activated")

      startForegroundObservation()
    case .background:
      Self.log.debug("backgrounded")

      stopForegroundObservation()
      backgroundTaskScheduler.scheduleNext()
    default:
      break
    }
  }

  // MARK: - Foreground Observation

  // A feed refresh bumps `contentUpdatedAt` across a burst of episodes while
  // playback ticks write in parallel. `embeddingWorkSignal` ignores the
  // playback-path columns, and this debounce collapses each burst into a single
  // `episodesNeedingEmbeddings` scan once the writes settle — so the heavy
  // three-table join never runs per-commit on the database writer.
  private let drainDebounce = Debounce(duration: .seconds(5), priority: .background)

  private func startForegroundObservation() {
    foregroundTask { task in
      guard task == nil else { return }
      task = Task(priority: taskPriority(.background)) {
        await contextualEmbedding.requestAndLoadAssetsIfNeeded()
        do {
          try await contextualEmbedding.assetsLoaded.wait()
        } catch {
          Self.log.caughtError(
            "Foreground embedding observation cancelled before assets loaded",
            error
          )
          return
        }
        guard !Task.isCancelled else { return }

        var retryDelay: Duration = .seconds(1)
        while !Task.isCancelled {
          do {
            for try await _ in observatory.embeddingWorkSignal() {
              guard !Task.isCancelled else { return }
              retryDelay = .seconds(1)
              scheduleDrain()
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
        let ids = try await recommendationRepo.episodesNeedingEmbeddings(
          revision: contextualEmbedding.revision
        )
        guard !ids.isEmpty else { return }
        try await EmbeddingService.upsertEpisodeEmbeddings(
          forIDs: ids,
          embedding: contextualEmbedding
        )
      } catch is CancellationError {
        // Superseded by a newer trigger or backgrounded mid-drain; the next
        // foreground pass re-queries any remaining work.
      } catch {
        Self.log.caughtError("Foreground embedding drain failed", error)
      }
    }
  }

  private func stopForegroundObservation() {
    drainDebounce.cancel()
    foregroundTask { task in
      task?.cancel()
      task = nil
    }
  }
}
