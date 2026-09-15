// Copyright Justin Bishop, 2026

import FactoryKit
import FactoryTesting
import Foundation
import GRDB
import Testing

@testable import PodHaven

@Suite("EmbeddingProcessor lifecycle coordination tests", .container)
struct EmbeddingProcessorLifecycleTests {
  @Test(
    "a cancelled background owner hands pending work to the waiting foreground drain",
    arguments: [false, true]
  )
  func cancelledOwnerResumesForeground(thermal: Bool) async throws {
    let fakeClock = Container.shared.fakeContinuousClock()
    fakeClock.freeze()
    let embedding = ContextualEmbedding(
      embedding: ScriptedEmbeddable { _ in
        fakeClock.advance(by: .seconds(1))
        return [1, 0, 0]
      }
    )
    Container.shared.contextualEmbedding.reset().register { embedding }.scope(.cached)
    Container.shared.embeddingWorkDemand.reset()
    let workDemand = Container.shared.embeddingWorkDemand()
    let scheduler = try #require(Container.shared.bgTaskScheduler() as? FakeBGTaskScheduler)
    let pacingSleeper = try #require(Container.shared.sleeper() as? FakeSleeper)
    let processor = Container.shared.embeddingProcessor()
    processor.register()
    defer { processor.handleScenePhaseChange(to: .background) }
    try await Wait.until({ scheduler.pendingIdentifiers.isEmpty }) {
      "Initial demand reconciliation did not finish"
    }
    let (_, episodes) = try await RecommendationHelpers.createPodcastWithEpisodes(count: 15)
    processor.workBecameAvailable()
    let identifier = try #require(scheduler.pendingIdentifiers.first)
    let task = try #require(scheduler.launchTask(withIdentifier: identifier))
    try await pacingSleeper.waitForSleepRequests(count: 1)
    let pacingDelay = try #require(pacingSleeper.pendingDurations().first)

    // Control the next foreground timer independently of the already suspended pacing sleep.
    let foregroundSleeper = FakeSleeper()
    Container.shared.sleeper.register { foregroundSleeper }
    if thermal {
      processor.handleThermalPressureChange(to: .serious)
      processor.handleThermalPressureChange(to: .nominal)
    } else {
      task.expire()
    }
    try await LogCapture.withSink { sink in
      processor.handleScenePhaseChange(to: .active)
      try await RecommendationHelpers.untilAdvancing({
        sink.captured()
          .contains {
            $0.message.contains("event=embeddingWorkSliceCompleted mode=foreground state=deferred")
          }
      }) {
        "Foreground drain did not defer to the cancelled owner"
      }
    }
    #expect(processor.isComputing)
    #expect(task.completionResults.isEmpty)

    fakeClock.advance(by: pacingDelay)
    await pacingSleeper.advanceTime(by: pacingDelay)
    try await RecommendationHelpers.untilAdvancing({ !workDemand.hasWork }) {
      "Cancelled owner lost the foreground retry; pending work needs another trigger"
    }
    let pending = try await Container.shared.recommendationRepo()
      .episodesNeedingEmbeddings(
        revision: embedding.revision
      )
    #expect(Set(pending).isDisjoint(with: episodes.map(\.id)))
    #expect(task.completionResults == [false])
  }

  @Test(
    "an older thermal suspension preserves the observer after recovery",
    arguments: [false, true]
  )
  func suspensionFinishingAfterRecovery(cycleScene: Bool) async throws {
    let processor = Container.shared.embeddingProcessor()
    let repo = Container.shared.recommendationRepo()
    let workDemand = Container.shared.embeddingWorkDemand()
    let fakeObservatory = try #require(Container.shared.observatory() as? FakeObservatory)
    let (initialPodcast, initialEpisodes) =
      try await RecommendationHelpers.createPodcastWithEpisodes(
        count: 1,
        podcastTitle: "Before overlapping lifecycle changes"
      )
    let initialEpisode = try #require(initialEpisodes.first)
    try await Container.shared.appDB().unsafeTestDB
      .write { db in
        let initialDate = Date.now.addingTimeInterval(-60)
        try Episode.filter(key: initialEpisode.id)
          .updateAll(db, Episode.Columns.contentUpdatedAt.set(to: initialDate))
        try Podcast.filter(key: initialPodcast.id)
          .updateAll(db, Podcast.Columns.contentUpdatedAt.set(to: initialDate))
      }

    processor.handleScenePhaseChange(to: .active)
    defer { processor.handleScenePhaseChange(to: .background) }
    try await RecommendationHelpers.untilAdvancing({
      try await repo.embedding(for: initialEpisode.id) != nil && !workDemand.hasWork
    }) {
      "Initial foreground work did not complete"
    }

    let recovered = ThreadSafe(false)
    try await LogCapture.withSink(
      onCapture: { event in
        guard event.message == "Suspending embedding work for thermal pressure=serious" else {
          return
        }
        if cycleScene { processor.handleScenePhaseChange(to: .background) }
        processor.handleThermalPressureChange(to: .nominal)
        if cycleScene { processor.handleScenePhaseChange(to: .active) }
        recovered(true)
      }
    ) { _ in
      processor.handleThermalPressureChange(to: .serious)
      #expect(recovered())

      let (_, episodes) = try await RecommendationHelpers.createPodcastWithEpisodes(
        count: 1,
        podcastTitle: "After overlapping lifecycle changes"
      )
      let episode = try #require(episodes.first)
      try await RecommendationHelpers.untilAdvancing({
        try await repo.embedding(for: episode.id) != nil && !workDemand.hasWork
      }) {
        "Recovered observer did not process new work without an extra lifecycle cycle"
      }
    }

    _ = try fakeObservatory.expectCalls(
      methodName: "embeddingWorkSignal",
      count: cycleScene ? 2 : 1
    )
  }

  @Test(
    "suspension cancels observation and one resumption drains retained demand",
    arguments: [false, true]
  )
  func suspensionCancelsObservation(thermal: Bool) async throws {
    let processor = Container.shared.embeddingProcessor()
    let repo = Container.shared.recommendationRepo()
    let workDemand = Container.shared.embeddingWorkDemand()
    let fakeObservatory = try #require(Container.shared.observatory() as? FakeObservatory)
    let reader = Container.shared.appDB().unsafeTestDB
    let cancellations = ThreadSafe(0)
    fakeObservatory.embeddingWorkSignalScript(
      (0..<2)
        .map { _ in
          { @Sendable in
            ValueObservation.tracking { db in
              (
                latestEpisodeContentUpdate: Date(
                  timeIntervalSince1970: Double(try Episode.fetchCount(db))
                ),
                latestPodcastContentUpdate: Optional<Date>.none
              )
            }
            .handleEvents(didCancel: { cancellations { $0 += 1 } })
            .values(in: reader)
          }
        }
    )

    processor.handleScenePhaseChange(to: .active)
    defer { processor.handleScenePhaseChange(to: .background) }
    try await RecommendationHelpers.untilAdvancing({ !workDemand.hasWork }) {
      "Initial observer did not reconcile demand"
    }

    if thermal {
      processor.handleThermalPressureChange(to: .critical)
    } else {
      processor.handleScenePhaseChange(to: .background)
    }
    try await Wait.until({ cancellations() == 1 }) {
      "Suspension left its foreground observer subscribed"
    }

    let (_, episodes) = try await RecommendationHelpers.createPodcastWithEpisodes(count: 1)
    let episode = try #require(episodes.first)
    processor.workBecameAvailable()
    #expect(workDemand.hasWork)
    #expect(try await repo.embedding(for: episode.id) == nil)
    _ = try fakeObservatory.expectCalls(methodName: "embeddingWorkSignal", count: 1)

    if thermal { processor.handleThermalPressureChange(to: .nominal) }
    processor.handleScenePhaseChange(to: .active)
    processor.handleScenePhaseChange(to: .active)
    try await RecommendationHelpers.untilAdvancing({
      try await repo.embedding(for: episode.id) != nil && !workDemand.hasWork
    }) {
      "Retained demand did not complete on the first resumption"
    }
    _ = try fakeObservatory.expectCalls(methodName: "embeddingWorkSignal", count: 2)
    #expect(cancellations() == 1)
    processor.handleScenePhaseChange(to: .background)
    try await Wait.until({ cancellations() == 2 }) {
      "Final backgrounding left an observer subscribed"
    }
  }
}
