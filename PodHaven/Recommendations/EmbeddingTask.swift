// Copyright Justin Bishop, 2026

import BackgroundTasks
import FactoryKit
import Foundation
import Logging
import SwiftUI

// MARK: - Container

extension Container {
  var embeddingTask: Factory<EmbeddingTask> {
    Factory(self) { EmbeddingTask() }.scope(.cached)
  }
}

// MARK: - EmbeddingTask

struct EmbeddingTask: Sendable {
  @DynamicInjected(\.embeddingService) private var embeddingService
  @DynamicInjected(\.repo) private var repo

  private static let log = Log.as(LogSubsystem.Recommendations.backgroundTask)

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

      guard let embedding = Container.shared.embeddingService().resolveEmbedding() else {
        Self.log.info("Contextual embedding assets not available yet, skipping")
        complete(true)
        return
      }

      do {
        let embeddingService = Container.shared.embeddingService()
        let repo = Container.shared.repo()

        let signalEpisodes = try await repo.allSignalEpisodes()
        let candidates = try await repo.allCandidateEpisodes(excludingOnDeckID: nil)

        let allEpisodeIDs: [Episode.ID] = (signalEpisodes + candidates).map { $0.id }
        let existingEmbeddings = try await repo.embeddings(for: allEpisodeIDs)
        let validIDs: Set<Episode.ID> = Set(existingEmbeddings.map { $0.episodeId })

        let priorityEpisodes = signalEpisodes.filter { !validIDs.contains($0.id) }
        let candidateEpisodes = candidates.filter { !validIDs.contains($0.id) }
        let episodesToEmbed = priorityEpisodes + candidateEpisodes

        if episodesToEmbed.isEmpty {
          Self.log.info("No episodes need embedding computation")
          complete(true)
          return
        }

        Self.log.info("Computing embeddings for \(episodesToEmbed.count) episodes")

        try await embeddingService.ensureEmbeddings(
          for: episodesToEmbed,
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
      backgroundTaskScheduler.scheduleNextIfNeeded()
    default:
      break
    }
  }

}
