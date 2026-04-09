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
  @DynamicInjected(\.embeddingService) private var embeddingService
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

      guard let embedding = Container.shared.embeddingProvider() else {
        Self.log.info("Contextual embedding assets not available yet, skipping")
        complete(true)
        return
      }

      do {
        let embeddingService = Container.shared.embeddingService()
        let repo = Container.shared.repo()

        // Prioritize signal episodes (rated/finished) then candidates.
        // ensureEmbeddings handles staleness checks internally — it skips
        // episodes whose cached embedding is still fresh (matching sourceHash
        // and embeddingRevision), and upserts stale or missing ones.
        let signalEpisodes = try await repo.allSignalEpisodes()
        let candidates = try await repo.allCandidateEpisodes()
        let episodesToProcess = signalEpisodes + candidates

        if episodesToProcess.isEmpty {
          Self.log.info("No episodes to process")
          complete(true)
          return
        }

        Self.log.info("Processing \(episodesToProcess.count) episodes for embedding freshness")

        try await embeddingService.ensureEmbeddings(
          for: episodesToProcess,
          embedding: embedding,
          checkCancellation: true
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

      embeddingService.requestContextualAssetsIfNeeded()
    case .background:
      Self.log.debug("backgrounded")

      backgroundTaskScheduler.scheduleNext()
    default:
      break
    }
  }
}
