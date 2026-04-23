// Copyright Justin Bishop, 2026

import BackgroundTasks
import FactoryKit
import Foundation
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
  @DynamicInjected(\.repo) private var repo

  private static let log = Log.as(LogSubsystem.Recommendations.processor)

  private static let backgroundTaskIdentifier = "\(AppInfo.bundleIdentifier).embeddingComputation"

  private let backgroundTaskScheduler: BackgroundTaskScheduler

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

      let embedding = Container.shared.contextualEmbedding()
      embedding.loadAssetsIfAvailable()
      guard embedding.isAvailable else {
        Self.log.info("Contextual embedding assets not available yet, skipping")
        complete(true)
        return
      }

      do {
        // Query returns only episode IDs that actually need embedding work:
        // no existing embedding, wrong revision, or content changed since
        // last computation. Signal episodes (rated/finished) are ordered first.
        // IDs only — full Episode rows are hydrated in chunks as they are
        // processed so a BG-expiry doesn't waste a multi-second hydration pass.
        let queryStart = ContinuousClock.now
        let idsToProcess = try await repo.episodesNeedingEmbeddings(
          revision: embedding.revision
        )
        let queryDuration = ContinuousClock.now - queryStart
        Self.log.debug("episodesNeedingEmbeddings query took \(queryDuration)")

        if idsToProcess.isEmpty {
          Self.log.info("No episodes need embedding updates")
          complete(true)
          return
        }

        Self.log.info("Processing \(idsToProcess.count) episodes for embeddings")

        try await EmbeddingService.upsertEpisodeEmbeddings(
          forIDs: idsToProcess,
          embedding: embedding
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

      Container.shared.contextualEmbedding().requestAndLoadAssetsIfNeeded()
    case .background:
      Self.log.debug("backgrounded")

      backgroundTaskScheduler.scheduleNext()
    default:
      break
    }
  }
}
