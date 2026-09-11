// Copyright Justin Bishop, 2026

import FactoryKit
import FactoryTesting
import Testing

@testable import PodHaven

@Suite("Background task registration", .container)
struct BackgroundTaskRegistrationTests {
  @Test("work arriving before registration waits for a successful handler")
  func workWaitsForRegistration() throws {
    let fake = try #require(Container.shared.bgTaskScheduler() as? FakeBGTaskScheduler)
    let hasWork = ThreadSafe(false)
    let scheduler = BackgroundTaskScheduler(
      identifier: "test.registration",
      cadence: .minutes(1),
      taskType: .processing(requiresNetworkConnectivity: false),
      executionPriority: .background,
      schedulingMode: .onDemand { hasWork() }
    )

    hasWork(true)
    scheduler.scheduleNext()
    scheduler.scheduleNext()
    #expect(fake.pendingTaskRequestsCallCount == 0)
    #expect(fake.submissions.isEmpty)

    scheduler.register { complete in complete(true) }
    #expect(fake.registrations.count == 1)
    #expect(fake.submissions.count == 1)
    #expect(fake.pendingIdentifiers == ["test.registration"])
  }

  @Test("work cleared before registration leaves no pending request")
  func clearedWorkDoesNotScheduleAfterRegistration() throws {
    let fake = try #require(Container.shared.bgTaskScheduler() as? FakeBGTaskScheduler)
    let hasWork = ThreadSafe(true)
    let scheduler = BackgroundTaskScheduler(
      identifier: "test.registration",
      cadence: .minutes(1),
      taskType: .appRefresh,
      executionPriority: .background,
      schedulingMode: .onDemand { hasWork() }
    )

    scheduler.scheduleNext()
    hasWork(false)
    scheduler.register { complete in complete(true) }

    #expect(fake.submissions.isEmpty)
    #expect(fake.pendingIdentifiers.isEmpty)
  }

  @Test("scheduling during registration waits for the system result")
  func schedulingWaitsForRegistrationToReturn() throws {
    let fake = try #require(Container.shared.bgTaskScheduler() as? FakeBGTaskScheduler)
    let scheduler = BackgroundTaskScheduler(
      identifier: "test.registration",
      cadence: .minutes(1),
      taskType: .appRefresh,
      executionPriority: .background
    )
    fake.setBeforeRegistration {
      scheduler.scheduleNext()
      scheduler.register { complete in complete(true) }
      #expect(fake.pendingTaskRequestsCallCount == 0)
      #expect(fake.submissions.isEmpty)
    }
    defer { fake.setBeforeRegistration(nil) }

    scheduler.register { complete in complete(true) }

    #expect(fake.registrations.count == 1)
    #expect(fake.submissions.count == 1)
  }

  @Test("failed registration prevents later submission attempts")
  func failedRegistrationNeverSubmits() throws {
    let fake = try #require(Container.shared.bgTaskScheduler() as? FakeBGTaskScheduler)
    let scheduler = BackgroundTaskScheduler(
      identifier: "test.registration",
      cadence: .minutes(1),
      taskType: .appRefresh,
      executionPriority: .background
    )
    fake.setRegisterResult(false)

    scheduler.register { complete in complete(true) }
    scheduler.scheduleNext()
    scheduler.register { complete in complete(true) }

    #expect(fake.registrations.count == 1)
    #expect(fake.pendingTaskRequestsCallCount == 0)
    #expect(fake.submissions.isEmpty)
  }

  @Test("scheduler instances share registration for the same identifier")
  func instancesShareRegistration() throws {
    let fake = try #require(Container.shared.bgTaskScheduler() as? FakeBGTaskScheduler)
    let first = BackgroundTaskScheduler(
      identifier: "test.registration",
      cadence: .minutes(1),
      taskType: .appRefresh,
      executionPriority: .background
    )
    let second = BackgroundTaskScheduler(
      identifier: "test.registration",
      cadence: .minutes(1),
      taskType: .appRefresh,
      executionPriority: .background
    )

    first.register { complete in complete(true) }
    second.register { complete in complete(true) }
    fake.setPendingIdentifiers([])
    second.scheduleNext()

    #expect(fake.registrations.count == 1)
    #expect(fake.submissions.count == 2)
  }

  @Test(
    "hot startup retains embedding and transcription work until registration",
    arguments: [ThermalPressure.serious, .critical]
  )
  func hotStartupWaitsForRegistration(pressure: ThermalPressure) async throws {
    let fake = try #require(Container.shared.bgTaskScheduler() as? FakeBGTaskScheduler)
    let (_, episodes) = try await RecommendationHelpers.createPodcastWithEpisodes(
      count: 1,
      podcastTitle: "Startup thermal work"
    )
    let episode = try #require(episodes.first)
    let store = FakeTranscriptionQueueStore(episodeIDs: [episode.id])
    Container.shared.transcriptionQueueStore.register { store }
    Container.shared.currentThermalPressure.context(.test) { { pressure } }
    let queue = Container.shared.transcriptionQueue()
    await queue.waitUntilLoaded()
    let demand = Container.shared.embeddingWorkDemand()
    demand.ensureAvailable()

    Container.shared.thermalPressureMonitor().start()

    #expect(Container.shared.sharedState().thermalPressure == pressure)
    #expect(demand.hasWork)
    #expect(queue.episodeIDs == [episode.id])
    #expect(fake.pendingTaskRequestsCallCount == 0)
    #expect(fake.submissions.isEmpty)

    Container.shared.embeddingProcessor().register()
    Container.shared.transcriptionProcessor().register()

    let identifiers = [
      "\(AppInfo.bundleIdentifier).embeddingComputation",
      "\(AppInfo.bundleIdentifier).transcription",
    ]
    #expect(fake.pendingIdentifiers == Set(identifiers))
    for identifier in identifiers {
      let task = try #require(fake.launchTask(withIdentifier: identifier))
      try await Wait.until(
        { task.completionResults == [true] },
        { "Registered background work did not defer under thermal pressure" }
      )
    }
    #expect(demand.hasWork)
    #expect(queue.episodeIDs == [episode.id])
  }
}
