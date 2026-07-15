// Copyright Justin Bishop, 2026

import FactoryKit
import FactoryTesting
import Foundation
import GRDB
import SwiftUI
import Testing

@testable import PodHaven

@Suite("EmbeddingProcessor tests", .container)
class EmbeddingProcessorTests {
  @DynamicInjected(\.bgTaskScheduler) private var bgTaskScheduler
  @DynamicInjected(\.embeddingWorkDemand) private var embeddingWorkDemand
  @DynamicInjected(\.observatory) private var observatory
  @DynamicInjected(\.recommendationRepo) private var recommendationRepo
  @DynamicInjected(\.contextualEmbedding) private var contextualEmbedding

  private var fakeBGTaskScheduler: FakeBGTaskScheduler {
    bgTaskScheduler as! FakeBGTaskScheduler
  }

  @Test("registration leaves no background request pending when there is no work")
  func registrationWithoutWorkLeavesNoPendingRequest() async throws {
    let fakeBGTaskScheduler = self.fakeBGTaskScheduler
    let processor = EmbeddingProcessor()

    processor.register()

    try await Wait.until(
      { fakeBGTaskScheduler.pendingIdentifiers.isEmpty },
      { "An empty embedding backlog should not leave a background request pending" }
    )
  }

  @Test("background work schedules one deduplicated processing request one minute later")
  func backgroundWorkSchedulesOneMinuteRequest() async throws {
    let fakeBGTaskScheduler = self.fakeBGTaskScheduler
    let processor = EmbeddingProcessor()
    processor.register()
    try await waitForNoPendingBackgroundRequest()
    let submissionCount = fakeBGTaskScheduler.submissions.count

    let before = Date.now
    processor.workBecameAvailable()
    processor.workBecameAvailable()
    let after = Date.now

    try await Wait.until(
      { fakeBGTaskScheduler.submissions.count == submissionCount + 1 },
      { "Embedding work did not schedule exactly one background request" }
    )
    let request = try #require(fakeBGTaskScheduler.submissions.last)
    #expect(request.isProcessing)
    #expect(fakeBGTaskScheduler.pendingIdentifiers.count == 1)
    if let earliestBeginDate = request.earliestBeginDate {
      #expect(earliestBeginDate >= before.addingTimeInterval(60))
      #expect(earliestBeginDate <= after.addingTimeInterval(60))
    } else {
      Issue.record("Embedding request should have an earliest begin date")
    }
  }

  @Test("foreground work remains demanded when the app backgrounds before its drain")
  func foregroundWorkSurvivesBackgroundHandoff() async throws {
    let fakeBGTaskScheduler = self.fakeBGTaskScheduler
    let workDemand = embeddingWorkDemand
    let processor = EmbeddingProcessor()
    processor.register()
    try await waitForNoPendingBackgroundRequest()

    processor.handleScenePhaseChange(to: .active)
    processor.workBecameAvailable()
    processor.handleScenePhaseChange(to: .background)

    try await Wait.until(
      { fakeBGTaskScheduler.pendingIdentifiers.count == 1 },
      { "Backgrounding with embedding work should leave one request pending" }
    )
    #expect(workDemand.hasWork)
  }

  @Test("background expiration preserves demand and its successor request")
  func backgroundExpirationPreservesDemand() async throws {
    let fakeBGTaskScheduler = self.fakeBGTaskScheduler
    let fakeRecommendationRepo = try #require(
      recommendationRepo as? FakeRecommendationRepo
    )
    let workDemand = embeddingWorkDemand
    let processor = EmbeddingProcessor()
    processor.register()
    try await waitForNoPendingBackgroundRequest()

    let (_, episodes) = try await RecommendationHelpers.createPodcastWithEpisodes(
      count: 2,
      podcastTitle: "Expiration"
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

    task.expire()

    try await Wait.until(
      { task.completionResults == [false] },
      { "Expired embedding task did not complete unsuccessfully" }
    )
    #expect(workDemand.hasWork)
    #expect(fakeBGTaskScheduler.pendingIdentifiers == [identifier])
  }

  @Test("persisted demand rejects a stale clear after new work arrives")
  func persistedDemandRejectsStaleClear() throws {
    let demand = embeddingWorkDemand
    let initial = demand.snapshot()
    #expect(demand.clear(ifUnchanged: initial))

    Container.shared.embeddingWorkDemand.reset()
    let restoredIdle = Container.shared.embeddingWorkDemand()
    #expect(!restoredIdle.hasWork)

    restoredIdle.markAvailable()
    let stale = restoredIdle.snapshot()
    restoredIdle.markAvailable()

    #expect(!restoredIdle.clear(ifUnchanged: stale))
    Container.shared.embeddingWorkDemand.reset()
    #expect(Container.shared.embeddingWorkDemand().hasWork)
  }

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

    let workDemand = embeddingWorkDemand
    try await Wait.until(
      { !workDemand.hasWork },
      { "A successful foreground drain did not clear embedding demand" }
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

  private func waitForNoPendingBackgroundRequest() async throws {
    let fakeBGTaskScheduler = self.fakeBGTaskScheduler
    try await Wait.until(
      { fakeBGTaskScheduler.pendingIdentifiers.isEmpty },
      { "Expected initial embedding-demand reconciliation to cancel its request" }
    )
  }
}
