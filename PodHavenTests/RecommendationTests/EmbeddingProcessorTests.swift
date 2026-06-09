// Copyright Justin Bishop, 2026

import FactoryKit
import FactoryTesting
import Foundation
import GRDB
import SwiftUI
import Testing

@testable import PodHaven

@Suite("EmbeddingProcessor foreground observation tests", .container)
class EmbeddingProcessorTests {
  @DynamicInjected(\.observatory) private var observatory
  @DynamicInjected(\.recommendationRepo) private var recommendationRepo
  @DynamicInjected(\.contextualEmbedding) private var contextualEmbedding

  @Test("scenePhase .active drains episodesNeedingEmbeddings")
  func activeDrainsBacklog() async throws {
    let (_, episodes) = try await RecommendationHelpers.createPodcastWithEpisodes(
      count: 3,
      podcastTitle: "Foreground"
    )

    let processor = EmbeddingProcessor()
    processor.handleScenePhaseChange(to: .active)

    try await waitForEmbeddings(
      of: episodes,
      reason: "Foreground observation did not embed all episodes"
    )

    processor.handleScenePhaseChange(to: .background)
  }

  @Test("scenePhase .background cancels the foreground task")
  func backgroundCancelsTask() async throws {
    let (podcast, initial) = try await RecommendationHelpers.createPodcastWithEpisodes(
      count: 2,
      podcastTitle: "Initial"
    )

    let processor = EmbeddingProcessor()
    processor.handleScenePhaseChange(to: .active)

    try await waitForEmbeddings(of: initial, reason: "Initial backlog did not drain")

    processor.handleScenePhaseChange(to: .background)

    let newEpisodes = try await RecommendationHelpers.addEpisodes(
      to: podcast,
      count: 2,
      pubDateOffset: { i in TimeInterval(-(i + 100) * 86400) }
    )

    // If the cancelled task were still alive, the GRDB emission triggered by
    // inserting `newEpisodes` would arm the drain debounce; advancing the
    // FakeSleeper each poll would then fire it and shrink pendingNew. Poll for
    // consecutive stable reads — cancellation leaks fail loudly via timeout.
    let recommendationRepo = self.recommendationRepo
    let revision = contextualEmbedding.revision
    let newIDs = Set(newEpisodes.map(\.id))
    let stableReads = ThreadSafe(0)
    let requiredStable = 30

    try await RecommendationHelpers.untilAdvancing({
      let pending = try await recommendationRepo.episodesNeedingEmbeddings(revision: revision)
      let pendingNew = Set(pending).intersection(newIDs)
      guard pendingNew.count == newEpisodes.count else {
        stableReads { $0 = 0 }
        return false
      }
      let current = stableReads { reads in
        reads += 1
        return reads
      }
      return current >= requiredStable
    }) {
      "Foreground task processed new episodes after .background (cancellation leaked)"
    }
  }

  @Test("repeated .active is idempotent — one task at a time")
  func repeatedActiveIsIdempotent() async throws {
    let fakeObservatory = try #require(observatory as? FakeObservatory)
    let (_, episodes) = try await RecommendationHelpers.createPodcastWithEpisodes(
      count: 2,
      podcastTitle: "Idempotent"
    )

    let processor = EmbeddingProcessor()
    processor.handleScenePhaseChange(to: .active)
    processor.handleScenePhaseChange(to: .active)
    processor.handleScenePhaseChange(to: .active)

    try await waitForEmbeddings(
      of: episodes,
      reason: "Episodes not embedded after repeated .active"
    )

    // Verify the single-task guard: three .active calls but only one
    // observatory subscription. Without the `guard task == nil` in
    // startForegroundObservation, this would be 3.
    _ = try fakeObservatory.expectCalls(methodName: "embeddingWorkSignal", count: 1)

    processor.handleScenePhaseChange(to: .background)
  }

  @Test("foreground observation retries after a transient failure")
  func observationRetriesAfterFailure() async throws {
    let fakeObservatory = try #require(observatory as? FakeObservatory)
    let dbReader = Container.shared.appDB().unsafeTestDB
    fakeObservatory.embeddingWorkSignalScript([
      {
        ValueObservation
          .tracking { _ -> EmbeddingWorkSignal in
            throw TestError.simulatedFailure
          }
          .values(in: dbReader)
      }
    ])

    let (_, episodes) = try await RecommendationHelpers.createPodcastWithEpisodes(
      count: 2,
      podcastTitle: "Retry"
    )

    let processor = EmbeddingProcessor()
    processor.handleScenePhaseChange(to: .active)

    let recommendationRepo = self.recommendationRepo
    let revision = contextualEmbedding.revision
    let episodeIDs = Set(episodes.map(\.id))
    try await RecommendationHelpers.untilAdvancing({
      let pending = try await recommendationRepo.episodesNeedingEmbeddings(revision: revision)
      return Set(pending).intersection(episodeIDs).isEmpty
    }) {
      "Foreground observation did not recover after failure"
    }

    processor.handleScenePhaseChange(to: .background)
  }

  // MARK: - Helpers

  private func waitForEmbeddings(of episodes: [Episode], reason: String) async throws {
    let recommendationRepo = self.recommendationRepo
    let revision = contextualEmbedding.revision
    let episodeIDs = Set(episodes.map(\.id))
    // The drain runs behind a Debounce, so advance the FakeSleeper each poll to
    // fire whatever sleep is currently armed.
    try await RecommendationHelpers.untilAdvancing({
      let pending = try await recommendationRepo.episodesNeedingEmbeddings(revision: revision)
      return Set(pending).intersection(episodeIDs).isEmpty
    }) {
      reason
    }
  }
}
