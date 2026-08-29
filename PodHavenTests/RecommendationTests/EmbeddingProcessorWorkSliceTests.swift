// Copyright Justin Bishop, 2026

import FactoryKit
import FactoryTesting
import Foundation
import SwiftUI
import Testing

@testable import PodHaven

@Suite("EmbeddingProcessor work slice tests", .container)
class EmbeddingProcessorWorkSliceTests {
  @DynamicInjected(\.bgTaskScheduler) private var bgTaskScheduler
  @DynamicInjected(\.contextualEmbedding) private var contextualEmbedding
  @DynamicInjected(\.embeddingWorkDemand) private var embeddingWorkDemand
  @DynamicInjected(\.recommendationRepo) private var recommendationRepo

  private var fakeBGTaskScheduler: FakeBGTaskScheduler {
    bgTaskScheduler as! FakeBGTaskScheduler
  }

  @Test("background grant processes one bounded work slice")
  func backgroundGrantProcessesOneBoundedWorkSlice() async throws {
    let fakeBGTaskScheduler = self.fakeBGTaskScheduler
    let fakeRecommendationRepo = try #require(
      recommendationRepo as? FakeRecommendationRepo
    )
    let workDemand = embeddingWorkDemand
    let (_, episodes) = try await RecommendationHelpers.createPodcastWithEpisodes(
      count: 17,
      podcastTitle: "Bounded Background Slice"
    )

    let processor = EmbeddingProcessor()
    processor.register()
    try await Wait.until(
      { fakeBGTaskScheduler.pendingIdentifiers.count == 1 },
      { "Embedding work did not schedule its background request" }
    )
    let identifier = try #require(fakeBGTaskScheduler.pendingIdentifiers.first)
    fakeRecommendationRepo.clearAllCalls()

    let task = try #require(
      fakeBGTaskScheduler.launchTask(withIdentifier: identifier)
    )
    try await Wait.until(
      { task.completionResults == [true] },
      { "Embedding background task did not complete its bounded slice" }
    )

    let hydrationCalls =
      fakeRecommendationRepo
      .calls(of: MethodCall<[Episode.ID]>.self)
      .filter { $0.methodName == "episodes" }
    let hydratedIDs = hydrationCalls.flatMap(\.parameters)
    #expect(hydratedIDs.count == 16)
    #expect(Set(hydratedIDs).isSubset(of: Set(episodes.map(\.id))))

    let pendingIDs = try await recommendationRepo.episodesNeedingEmbeddings(
      revision: contextualEmbedding.revision
    )
    #expect(pendingIDs.count == 1)
    #expect(workDemand.hasWork)
    #expect(fakeBGTaskScheduler.pendingIdentifiers == [identifier])

    let successorTask = try #require(
      fakeBGTaskScheduler.launchTask(withIdentifier: identifier)
    )
    try await Wait.until(
      { successorTask.completionResults == [true] },
      { "Embedding successor task did not complete the remaining slice" }
    )
    #expect(
      try await recommendationRepo.episodesNeedingEmbeddings(
        revision: contextualEmbedding.revision
      )
      .isEmpty
    )
    #expect(!workDemand.hasWork)
    #expect(fakeBGTaskScheduler.pendingIdentifiers.isEmpty)
  }

  @Test("slow background slice emits a Sentry-visible summary warning")
  func slowBackgroundSliceEmitsSummaryWarning() async throws {
    let clock = Container.shared.fakeContinuousClock()
    clock.freeze()
    let slowEmbedding = ContextualEmbedding(
      embedding: ScriptedEmbeddable { _ in
        clock.advance(by: .seconds(25))
        return [1, 0, 0]
      }
    )
    Container.shared.contextualEmbedding.reset()
      .register { slowEmbedding }
      .scope(.cached)
    Container.shared.embeddingWorkDemand.reset()

    _ = try await RecommendationHelpers.createPodcastWithEpisodes(
      count: 1,
      podcastTitle: "Slow Background Slice"
    )

    let captured = try await LogCapture.withSink { sink in
      let fakeBGTaskScheduler = self.fakeBGTaskScheduler
      let processor = EmbeddingProcessor()
      processor.register()
      try await Wait.until(
        { fakeBGTaskScheduler.pendingIdentifiers.count == 1 },
        { "Slow embedding work did not schedule its background request" }
      )
      let identifier = try #require(fakeBGTaskScheduler.pendingIdentifiers.first)
      let task = try #require(
        fakeBGTaskScheduler.launchTask(withIdentifier: identifier)
      )
      try await Wait.until(
        { task.completionResults == [true] },
        { "Slow embedding background task did not complete" }
      )
      return sink.captured()
    }

    let summary = try #require(
      captured.first {
        $0.message.contains("event=embeddingWorkSliceCompleted")
      }
    )
    #expect(summary.level == .warning)
    #expect(summary.message.contains("mode=background"))
    #expect(summary.message.contains("state=empty"))
    #expect(summary.message.contains("processedCount=1"))
    #expect(summary.message.contains("failedEpisodeCount=0"))
    #expect(summary.message.contains("wallSeconds="))
  }

  @Test("foreground drains continue through bounded work slices")
  func foregroundDrainsContinueThroughBoundedWorkSlices() async throws {
    let fakeRecommendationRepo = try #require(
      recommendationRepo as? FakeRecommendationRepo
    )
    let (_, episodes) = try await RecommendationHelpers.createPodcastWithEpisodes(
      count: 17,
      podcastTitle: "Bounded Foreground Slices"
    )
    fakeRecommendationRepo.clearAllCalls()

    let processor = EmbeddingProcessor()
    processor.handleScenePhaseChange(to: .active)

    try await waitForEmbeddings(
      of: episodes,
      reason: "Foreground embedding did not continue through all bounded slices"
    )

    let hydrationCalls =
      fakeRecommendationRepo
      .calls(of: MethodCall<[Episode.ID]>.self)
      .filter { $0.methodName == "episodes" }
    #expect(!hydrationCalls.isEmpty)
    #expect(hydrationCalls.allSatisfy { $0.parameters.count <= 16 })
    #expect(Set(hydrationCalls.flatMap(\.parameters)) == Set(episodes.map(\.id)))

    processor.handleScenePhaseChange(to: .background)
  }

  @Test("foreground handoff does not overlap a running background slice")
  func foregroundHandoffDoesNotOverlapRunningBackgroundSlice() async throws {
    let fakeBGTaskScheduler = self.fakeBGTaskScheduler
    let fakeRecommendationRepo = try #require(
      recommendationRepo as? FakeRecommendationRepo
    )
    let (_, episodes) = try await RecommendationHelpers.createPodcastWithEpisodes(
      count: 1,
      podcastTitle: "Foreground Background Handoff"
    )
    let episode = try #require(episodes.first)

    let processor = EmbeddingProcessor()
    processor.register()
    try await Wait.until(
      { fakeBGTaskScheduler.pendingIdentifiers.count == 1 },
      { "Embedding work did not schedule its background request" }
    )
    let identifier = try #require(fakeBGTaskScheduler.pendingIdentifiers.first)
    fakeRecommendationRepo.armEmbeddingsGate(matching: [episode.id])
    defer { fakeRecommendationRepo.releaseEmbeddingsGate() }

    let task = try #require(
      fakeBGTaskScheduler.launchTask(withIdentifier: identifier)
    )
    try await Wait.until(
      { fakeRecommendationRepo.isEmbeddingsGateSuspended },
      { "Background slice did not reach its repository gate" }
    )

    fakeRecommendationRepo.clearAllCalls()
    let captured = try await LogCapture.withSink { sink in
      processor.handleScenePhaseChange(to: .active)
      try await RecommendationHelpers.untilAdvancing(
        {
          sink.captured()
            .contains {
              $0.message.contains("event=embeddingWorkSliceCompleted")
                && $0.message.contains("mode=foreground")
                && $0.message.contains("state=deferred")
            }
        },
        { "Foreground drain did not defer to the running background slice" }
      )
      return sink.captured()
    }
    #expect(
      captured.contains {
        $0.message.contains("mode=foreground")
          && $0.message.contains("state=deferred")
      }
    )

    let foregroundHydrationCalls =
      fakeRecommendationRepo
      .calls(of: MethodCall<[Episode.ID]>.self)
      .filter { $0.methodName == "episodes" }
    #expect(foregroundHydrationCalls.isEmpty)

    fakeRecommendationRepo.releaseEmbeddingsGate()
    try await Wait.until(
      { task.completionResults == [true] },
      { "Background slice did not complete after its repository gate opened" }
    )
    processor.handleScenePhaseChange(to: .background)
  }

  private func waitForEmbeddings(of episodes: [Episode], reason: String) async throws {
    let recommendationRepo = self.recommendationRepo
    let revision = contextualEmbedding.revision
    let episodeIDs = Set(episodes.map(\.id))
    try await RecommendationHelpers.untilAdvancing({
      let pending = try await recommendationRepo.episodesNeedingEmbeddings(revision: revision)
      return Set(pending).intersection(episodeIDs).isEmpty
    }) {
      reason
    }
  }
}
