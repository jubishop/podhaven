// Copyright Justin Bishop, 2026

import FactoryKit
import FactoryTesting
import Testing

@testable import PodHaven

@Suite("EmbeddingProcessor thermal tests", .container)
class EmbeddingProcessorThermalTests {
  @DynamicInjected(\.bgTaskScheduler) private var bgTaskScheduler
  @DynamicInjected(\.embeddingWorkDemand) private var embeddingWorkDemand
  @DynamicInjected(\.recommendationRepo) private var recommendationRepo

  private var fakeBGTaskScheduler: FakeBGTaskScheduler {
    bgTaskScheduler as! FakeBGTaskScheduler
  }

  @Test("thermal pressure cancels the active embedding background grant")
  func thermalPressureCancelsActiveBackgroundGrant() async throws {
    let fakeBGTaskScheduler = self.fakeBGTaskScheduler
    let fakeRecommendationRepo = try #require(
      recommendationRepo as? FakeRecommendationRepo
    )
    let workDemand = embeddingWorkDemand
    let processor = EmbeddingProcessor()
    processor.register()
    try await Wait.until(
      { fakeBGTaskScheduler.pendingIdentifiers.isEmpty },
      { "Expected initial embedding-demand reconciliation to cancel its request" }
    )

    let (_, episodes) = try await RecommendationHelpers.createPodcastWithEpisodes(
      count: 2,
      podcastTitle: "Thermal background grant"
    )
    fakeRecommendationRepo.armEmbeddingsGate(matching: Set(episodes.map(\.id)))
    defer { fakeRecommendationRepo.releaseEmbeddingsGate() }

    processor.workBecameAvailable()
    try await Wait.until(
      { fakeBGTaskScheduler.pendingIdentifiers.count == 1 },
      { "Embedding work did not schedule its background request" }
    )
    let identifier = try #require(fakeBGTaskScheduler.pendingIdentifiers.first)
    let task = try #require(
      fakeBGTaskScheduler.launchTask(withIdentifier: identifier)
    )
    try await Wait.until(
      { fakeRecommendationRepo.isEmbeddingsGateSuspended },
      { "Embedding background task did not reach its suspended write" }
    )

    processor.handleThermalPressureChange(to: .critical)
    fakeRecommendationRepo.releaseEmbeddingsGate()

    try await Wait.until(
      { !task.completionResults.isEmpty },
      { "Thermal pressure did not finish the active embedding background grant" }
    )
    #expect(task.completionResults == [false])
    #expect(workDemand.hasWork)
    #expect(fakeBGTaskScheduler.pendingIdentifiers == [identifier])
  }
}
