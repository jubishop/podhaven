// Copyright Justin Bishop, 2026

import FactoryKit
import Foundation
import Testing

@testable import PodHaven

@Suite("EmbeddingProcessor pacing tests", .container)
struct EmbeddingProcessorPacingTests {
  @Test("short background embedding work remains unpaced")
  func shortBackgroundWorkRemainsUnpaced() async throws {
    let fakeClock = Container.shared.fakeContinuousClock()
    fakeClock.freeze()
    let embeddingCallCount = ThreadSafe(0)
    let embedding = ContextualEmbedding(
      embedding: ScriptedEmbeddable { _ in
        embeddingCallCount { $0 += 1 }
        fakeClock.advance(by: .seconds(1))
        return [1, 0, 0]
      }
    )
    Container.shared.contextualEmbedding.reset()
      .register { embedding }
      .scope(.cached)
    Container.shared.embeddingWorkDemand.reset()

    let fakeBGTaskScheduler = try #require(
      Container.shared.bgTaskScheduler() as? FakeBGTaskScheduler
    )
    let fakeSleeper = try #require(Container.shared.sleeper() as? FakeSleeper)
    let processor = EmbeddingProcessor()
    processor.register()
    try await Wait.until(
      { fakeBGTaskScheduler.pendingIdentifiers.isEmpty },
      { "Initial embedding-demand reconciliation did not finish" }
    )

    _ = try await RecommendationHelpers.createPodcastWithEpisodes(
      count: 14,
      podcastTitle: "Short Background Work"
    )
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
      { task.completionResults == [true] },
      { "Short background embedding work did not finish" }
    )
    #expect(embeddingCallCount() == 30)
    #expect(fakeSleeper.pendingDurations().isEmpty)
    #expect(!Container.shared.embeddingWorkDemand().hasWork)
  }

  @Test("sustained background embedding work pauses before continuing")
  func sustainedBackgroundWorkPausesBeforeContinuing() async throws {
    let fakeClock = Container.shared.fakeContinuousClock()
    fakeClock.freeze()
    let embeddingCallCount = ThreadSafe(0)
    let embedding = ContextualEmbedding(
      embedding: ScriptedEmbeddable { _ in
        embeddingCallCount { $0 += 1 }
        fakeClock.advance(by: .seconds(1))
        return [1, 0, 0]
      }
    )
    Container.shared.contextualEmbedding.reset()
      .register { embedding }
      .scope(.cached)
    Container.shared.embeddingWorkDemand.reset()

    let fakeBGTaskScheduler = try #require(
      Container.shared.bgTaskScheduler() as? FakeBGTaskScheduler
    )
    let fakeSleeper = try #require(Container.shared.sleeper() as? FakeSleeper)
    let processor = EmbeddingProcessor()
    processor.register()
    try await Wait.until(
      { fakeBGTaskScheduler.pendingIdentifiers.isEmpty },
      { "Initial embedding-demand reconciliation did not finish" }
    )

    _ = try await RecommendationHelpers.createPodcastWithEpisodes(
      count: 15,
      podcastTitle: "Sustained Background Work"
    )
    processor.workBecameAvailable()
    try await Wait.until(
      { fakeBGTaskScheduler.pendingIdentifiers.count == 1 },
      { "Embedding work did not schedule its background request" }
    )
    let identifier = try #require(fakeBGTaskScheduler.pendingIdentifiers.first)
    let task = try #require(
      fakeBGTaskScheduler.launchTask(withIdentifier: identifier)
    )

    try await fakeSleeper.waitForSleepRequests(count: 1)
    let pacingDelay = try #require(fakeSleeper.pendingDurations().first)
    #expect(abs(pacingDelay.asTimeInterval - 20) < 0.001)
    #expect(embeddingCallCount() == 30)
    #expect(task.completionResults.isEmpty)

    fakeClock.advance(by: pacingDelay)
    await fakeSleeper.advanceTime(by: pacingDelay)
    try await Wait.until(
      { task.completionResults == [true] },
      { "Background embedding work did not resume after pacing" }
    )
    #expect(embeddingCallCount() == 32)
    #expect(!Container.shared.embeddingWorkDemand().hasWork)
  }

  @Test("expiration during pacing preserves completed work")
  func expirationDuringPacingPreservesCompletedWork() async throws {
    let fakeClock = Container.shared.fakeContinuousClock()
    fakeClock.freeze()
    let embeddingCallCount = ThreadSafe(0)
    let embedding = ContextualEmbedding(
      embedding: ScriptedEmbeddable { _ in
        embeddingCallCount { $0 += 1 }
        fakeClock.advance(by: .seconds(1))
        return [1, 0, 0]
      }
    )
    Container.shared.contextualEmbedding.reset()
      .register { embedding }
      .scope(.cached)
    Container.shared.embeddingWorkDemand.reset()

    let fakeBGTaskScheduler = try #require(
      Container.shared.bgTaskScheduler() as? FakeBGTaskScheduler
    )
    let fakeSleeper = try #require(Container.shared.sleeper() as? FakeSleeper)
    let recommendationRepo = Container.shared.recommendationRepo()
    let processor = EmbeddingProcessor()
    processor.register()
    try await Wait.until(
      { fakeBGTaskScheduler.pendingIdentifiers.isEmpty },
      { "Initial embedding-demand reconciliation did not finish" }
    )

    let (_, episodes) = try await RecommendationHelpers.createPodcastWithEpisodes(
      count: 15,
      podcastTitle: "Expiring Background Work"
    )
    processor.workBecameAvailable()
    try await Wait.until(
      { fakeBGTaskScheduler.pendingIdentifiers.count == 1 },
      { "Embedding work did not schedule its background request" }
    )
    let identifier = try #require(fakeBGTaskScheduler.pendingIdentifiers.first)
    let task = try #require(
      fakeBGTaskScheduler.launchTask(withIdentifier: identifier)
    )

    try await fakeSleeper.waitForSleepRequests(count: 1)
    let pacingDelay = try #require(fakeSleeper.pendingDurations().first)
    task.expire()
    fakeClock.advance(by: pacingDelay)
    await fakeSleeper.advanceTime(by: pacingDelay)

    try await Wait.until(
      { task.completionResults == [false] },
      { "Expired background embedding work did not report cancellation" }
    )
    let pendingIDs = try await recommendationRepo.episodesNeedingEmbeddings(
      revision: embedding.revision
    )
    #expect(Set(pendingIDs).intersection(episodes.map(\.id)).count == 1)
    #expect(embeddingCallCount() == 30)
    #expect(Container.shared.embeddingWorkDemand().hasWork)
    #expect(fakeBGTaskScheduler.pendingIdentifiers == [identifier])
  }
}
