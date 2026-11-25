// Copyright Justin Bishop, 2026

import FactoryKit
import FactoryTesting
import Foundation
import GRDB
import SwiftUI
import Testing
import UIKit

@testable import PodHaven

@Suite("of RefreshScheduler tests", .container)
@MainActor struct RefreshSchedulerTests {
  @DynamicInjected(\.bgTaskScheduler) private var bgTaskScheduler
  @DynamicInjected(\.cacheManagerSession) private var cacheManagerSession
  @DynamicInjected(\.networkPathMonitor) private var networkPathMonitor
  @DynamicInjected(\.observatory) private var observatory
  @DynamicInjected(\.podcastFeedSession) private var podcastFeedSession
  @DynamicInjected(\.refreshScheduler) private var refreshScheduler
  @DynamicInjected(\.repo) private var repo
  @DynamicInjected(\.sleeper) private var sleeper
  @DynamicInjected(\.uiApplication) private var uiApplication

  private var cacheSession: FakeDataFetchable {
    cacheManagerSession as! FakeDataFetchable
  }
  private var fakeBGTaskScheduler: FakeBGTaskScheduler {
    bgTaskScheduler as! FakeBGTaskScheduler
  }
  private var feedRefreshSubmissionCount: Int {
    fakeBGTaskScheduler.submissions
      .filter {
        $0.identifier == "\(AppInfo.bundleIdentifier).feedRefresh"
      }
      .count
  }
  private var fakeApplication: FakeApplication {
    uiApplication as! FakeApplication
  }
  private var fakeNetworkPathMonitor: FakeNetworkPathMonitor {
    networkPathMonitor as! FakeNetworkPathMonitor
  }
  private var fakeObservatory: FakeObservatory {
    observatory as! FakeObservatory
  }
  private var fakeSleeper: FakeSleeper {
    sleeper as! FakeSleeper
  }
  private var session: FakeDataFetchable {
    podcastFeedSession as! FakeDataFetchable
  }

  @Test("foreground activation starts a single refresh loop after the initial delay")
  func foregroundActivationStartsRefreshLoop() async throws {
    let fakeApplication = fakeApplication
    let fakeSleeper = fakeSleeper
    let session = session
    let podcastSeries = try await makeStaleSubscribedSeries()
    let responseData = PreviewBundle.loadAsset(
      named: "hardfork_short_updated",
      in: .FeedRSS
    )
    let (startedSemaphore, finishSemaphore) = await session.releaseWaitRespond(
      to: podcastSeries.podcast.feedURL.rawValue,
      data: responseData
    )
    fakeApplication.applicationState = .active

    refreshScheduler.handleScenePhaseChange(to: .active)

    try await fakeSleeper.waitForSleepRequests(count: 1)
    #expect(await session.requests.isEmpty)

    await fakeSleeper.advanceTime(by: .seconds(3))
    try await startedSemaphore.waitUnlessCancelled()

    #expect(fakeApplication.activeTaskCount == 1)
    finishSemaphore.signal()

    try await Wait.until(
      { @MainActor in
        fakeApplication.activeTaskCount == 0
      },
      { @MainActor in
        "Expected foreground refresh background task to end"
      }
    )
    try await Wait.until(
      { await session.requests.count == 1 },
      { "Expected one foreground refresh request, got \(await session.requests.count)" }
    )
    try await fakeSleeper.waitForSleepRequests(count: 1)
  }

  @Test("backgrounding cancels the sleeping foreground loop and schedules a background task")
  func backgroundingCancelsSleepingForegroundLoop() async throws {
    refreshScheduler.register()
    fakeBGTaskScheduler.setPendingIdentifiers([])
    let initialSubmissionCount = feedRefreshSubmissionCount
    let fakeSleeper = fakeSleeper
    let session = session
    let podcastSeries = try await makeStaleSubscribedSeries()
    let responseData = PreviewBundle.loadAsset(
      named: "hardfork_short_updated",
      in: .FeedRSS
    )
    let (requestStarted, releaseResponse) = await session.releaseWaitRespond(
      to: podcastSeries.podcast.feedURL.rawValue,
      data: responseData
    )
    defer { releaseResponse.signal() }
    fakeApplication.applicationState = .active

    refreshScheduler.handleScenePhaseChange(to: .active)

    try await fakeSleeper.waitForSleepRequests(count: 1)
    await fakeSleeper.advanceTime(by: .seconds(3))
    try await requestStarted.waitUnlessCancelled()
    #expect(await session.requests.count == 1)
    releaseResponse.signal()
    try await fakeSleeper.waitForSleepRequests(count: 1)

    fakeApplication.applicationState = .background
    refreshScheduler.handleScenePhaseChange(to: .background)
    await fakeSleeper.advanceTime(by: .minutes(4))

    #expect(await session.requests.count == 1)
    #expect(feedRefreshSubmissionCount == initialSubmissionCount + 1)
  }

  @Test("duplicate active transitions do not create multiple foreground loops")
  func duplicateActiveTransitionsDoNotCreateMultipleForegroundLoops() async throws {
    let fakeApplication = fakeApplication
    let fakeSleeper = fakeSleeper
    let refreshScheduler = refreshScheduler
    let session = session
    let podcastSeries = try await makeStaleSubscribedSeries()
    let responseData = PreviewBundle.loadAsset(
      named: "hardfork_short_updated",
      in: .FeedRSS
    )
    let (startedSemaphore, finishSemaphore) = await session.releaseWaitRespond(
      to: podcastSeries.podcast.feedURL.rawValue,
      data: responseData
    )
    fakeApplication.applicationState = .active

    await withTaskGroup(of: Void.self) { group in
      for _ in 0..<8 {
        group.addTask { refreshScheduler.handleScenePhaseChange(to: .active) }
      }
    }

    try await fakeSleeper.waitForSleepRequests(count: 1)
    await fakeSleeper.advanceTime(by: .seconds(3))
    try await startedSemaphore.waitUnlessCancelled()

    for _ in 0..<10 {
      await Task.yield()
    }

    #expect(fakeApplication.activeTaskCount == 1)

    finishSemaphore.signal()

    try await Wait.until(
      { @MainActor in
        fakeApplication.activeTaskCount == 0
      },
      { @MainActor in
        "Expected duplicate active transitions to leave no foreground background tasks running"
      }
    )
  }

  @Test("backgrounding during an in-flight foreground refresh prevents loop re-arming")
  func backgroundingDuringForegroundRefreshPreventsRearming() async throws {
    refreshScheduler.register()
    fakeBGTaskScheduler.setPendingIdentifiers([])
    let initialSubmissionCount = feedRefreshSubmissionCount
    let fakeApplication = fakeApplication
    let fakeSleeper = fakeSleeper
    let session = session
    let podcastSeries = try await makeStaleSubscribedSeries()
    let responseData = PreviewBundle.loadAsset(
      named: "hardfork_short_updated",
      in: .FeedRSS
    )
    let (startedSemaphore, finishSemaphore) = await session.releaseWaitRespond(
      to: podcastSeries.podcast.feedURL.rawValue,
      data: responseData
    )
    fakeApplication.applicationState = .active

    refreshScheduler.handleScenePhaseChange(to: .active)

    try await fakeSleeper.waitForSleepRequests(count: 1)
    await fakeSleeper.advanceTime(by: .seconds(3))
    try await startedSemaphore.waitUnlessCancelled()

    #expect(fakeApplication.activeTaskCount == 1)

    fakeApplication.applicationState = .background
    refreshScheduler.handleScenePhaseChange(to: .background)
    finishSemaphore.signal()

    try await Wait.until(
      { @MainActor in
        fakeApplication.activeTaskCount == 0
      },
      { @MainActor in
        "Expected foreground refresh background task to end after backgrounding"
      }
    )

    await fakeSleeper.advanceTime(by: .minutes(4))

    #expect(await session.requests.count == 1)
    #expect(feedRefreshSubmissionCount == initialSubmissionCount + 1)
  }

  @Test("background refresh completion while backgrounded does not arm the foreground loop")
  func backgroundRefreshCompletionWhileBackgroundedDoesNotStartForegroundLoop() async throws {
    let fakeBGTaskScheduler = fakeBGTaskScheduler
    let fakeSleeper = fakeSleeper
    let session = session
    let podcastSeries = try await makeStaleSubscribedSeries()
    let responseData = PreviewBundle.loadAsset(
      named: "hardfork_short_updated",
      in: .FeedRSS
    )
    await session.respond(to: podcastSeries.podcast.feedURL.rawValue, data: responseData)
    fakeApplication.applicationState = .background

    refreshScheduler.register()

    let identifier = try #require(fakeBGTaskScheduler.submissions.first?.identifier)
    let task = try #require(fakeBGTaskScheduler.launchTask(withIdentifier: identifier))

    try await Wait.until(
      { task.completionResults == [true] },
      { "Expected background refresh to complete successfully, got \(task.completionResults)" }
    )
    try await Wait.until(
      { await session.requests.count == 1 },
      { "Expected one background refresh request, got \(await session.requests.count)" }
    )

    await fakeSleeper.advanceTime(by: .seconds(3))

    #expect(await session.requests.count == 1)
    #expect(fakeApplication.activeTaskCount == 0)
  }

  @Test(
    "active scene transition during a background refresh starts foreground looping only after the background refresh finishes"
  )
  func activeDuringBackgroundRefreshHandsOffToForegroundLoop() async throws {
    let fakeBGTaskScheduler = fakeBGTaskScheduler
    let fakeSleeper = fakeSleeper
    let session = session
    let podcastSeries = try await makeStaleSubscribedSeries()
    let responseData = PreviewBundle.loadAsset(
      named: "hardfork_short_updated",
      in: .FeedRSS
    )
    let (startedSemaphore, finishSemaphore) = await session.releaseWaitRespond(
      to: podcastSeries.podcast.feedURL.rawValue,
      data: responseData
    )
    fakeApplication.applicationState = .background

    refreshScheduler.register()

    let identifier = try #require(fakeBGTaskScheduler.submissions.first?.identifier)
    let task = try #require(fakeBGTaskScheduler.launchTask(withIdentifier: identifier))
    try await startedSemaphore.waitUnlessCancelled()

    fakeApplication.applicationState = .active
    refreshScheduler.handleScenePhaseChange(to: .active)
    await fakeSleeper.advanceTime(by: .seconds(3))
    #expect(await session.requests.count == 1)

    finishSemaphore.signal()
    await session.respond(to: podcastSeries.podcast.feedURL.rawValue, data: responseData)

    try await Wait.until(
      { task.completionResults == [true] },
      { "Expected background refresh to complete successfully, got \(task.completionResults)" }
    )
    try await fakeSleeper.waitForSleepRequests(count: 1)

    await fakeSleeper.advanceTime(by: .seconds(3))
    try await fakeSleeper.waitForSleepRequests(count: 1)
  }

  @Test("background refresh hands newly queued episodes to the cache session before completing")
  func backgroundRefreshCachesNewlyQueuedEpisodes() async throws {
    let fakeBGTaskScheduler = fakeBGTaskScheduler
    let session = session
    let podcastSeries = try await NewEpisodeFeed.insertSeries(
      lastUpdate: 5.hoursAgo,
      queueAllEpisodes: .onTop
    )
    await session.respond(to: podcastSeries.podcast.feedURL.rawValue, data: NewEpisodeFeed.data)
    fakeApplication.applicationState = .background
    // Only the refresh's handoff, not the queue observation, can start downloads.
    fakeObservatory.holdNextQueuedPodcastEpisodesDelivery()
    defer { fakeObservatory.releaseHeldQueuedPodcastEpisodesDelivery() }

    refreshScheduler.register()

    let identifier = try #require(fakeBGTaskScheduler.submissions.first?.identifier)
    let cacheDownloadTasks = await cacheSession.downloadTasks
    let downloadDescriptionsAtCompletion = ThreadSafe<Set<String>>([])
    let task = try #require(
      fakeBGTaskScheduler.launchTask(withIdentifier: identifier) {
        downloadDescriptionsAtCompletion(Set(cacheDownloadTasks().compactMap(\.taskDescription)))
      }
    )
    try await Wait.until(
      { task.completionResults == [true] },
      { "Expected background refresh to complete successfully, got \(task.completionResults)" }
    )

    let queuedEpisodeIDs = try await Container.shared.appDB().reader
      .read { db in
        try Episode.all().queued().selectID().fetchAll(db)
      }
    #expect(queuedEpisodeIDs.count == 1)
    for episodeID in queuedEpisodeIDs {
      #expect(downloadDescriptionsAtCompletion().contains(String(episodeID.rawValue)))
      let downloadTasks = await cacheSession.downloadTasks()
        .filter {
          $0.taskDescription == String(episodeID.rawValue)
        }
      #expect(downloadTasks.count == 1)
      for downloadTask in downloadTasks {
        #expect(await downloadTask.isResumed())
      }
    }
  }

  @Test(
    "background refresh waits for the first network path and skips a constrained connection until it clears",
    arguments: [
      FakeNetworkPath(isConstrained: true),
      FakeNetworkPath(isUltraConstrained: true),
    ]
  )
  func backgroundRefreshSkipsConstrainedFirstPath(constrainedPath: FakeNetworkPath) async throws {
    let fakeBGTaskScheduler = fakeBGTaskScheduler
    let fakeNetworkPathMonitor = fakeNetworkPathMonitor
    let session = session
    fakeNetworkPathMonitor.withholdInitialPath()
    let podcastSeries = try await makeStaleSubscribedSeries()
    let responseData = PreviewBundle.loadAsset(
      named: "hardfork_short_updated",
      in: .FeedRSS
    )
    await session.respond(to: podcastSeries.podcast.feedURL.rawValue, data: responseData)
    fakeApplication.applicationState = .background

    refreshScheduler.register()

    let identifier = try #require(fakeBGTaskScheduler.submissions.first?.identifier)
    let constrainedTask = try #require(fakeBGTaskScheduler.launchTask(withIdentifier: identifier))
    try await fakeNetworkPathMonitor.waitForStart()
    fakeNetworkPathMonitor.update(constrainedPath)

    try await Wait.until(
      { constrainedTask.completionResults == [true] },
      {
        "Expected constrained background refresh to complete successfully, got \(constrainedTask.completionResults)"
      }
    )
    let constrainedRequests = await session.requests
    #expect(constrainedRequests.isEmpty)

    fakeNetworkPathMonitor.update(FakeNetworkPath())
    let unconstrainedTask = try #require(
      fakeBGTaskScheduler.launchTask(withIdentifier: identifier)
    )

    try await Wait.until(
      { unconstrainedTask.completionResults == [true] },
      {
        "Expected unconstrained background refresh to complete successfully, got \(unconstrainedTask.completionResults)"
      }
    )
    let unconstrainedRequests = await session.requests
    #expect(unconstrainedRequests == [podcastSeries.podcast.feedURL.rawValue])
  }

  @Test("background refresh waits for the first network path and applies cellular staleness")
  func backgroundRefreshAppliesCellularStalenessOnExpensiveFirstPath() async throws {
    let fakeBGTaskScheduler = fakeBGTaskScheduler
    let fakeNetworkPathMonitor = fakeNetworkPathMonitor
    let session = session
    fakeNetworkPathMonitor.withholdInitialPath()
    // Background refresh treats this as stale on Wi-Fi but not on cellular.
    _ = try await makeStaleSubscribedSeries(
      feedData: SyntheticFeed.rss(index: 0, episodes: 1),
      feedURL: SyntheticFeed.url(0),
      lastUpdate: 3.hoursAgo
    )
    let cellularStaleSeries = try await makeStaleSubscribedSeries(
      feedData: SyntheticFeed.rss(index: 1, episodes: 1),
      feedURL: SyntheticFeed.url(1),
      lastUpdate: 5.hoursAgo
    )
    await SyntheticFeed.respond(session, episodes: 2)
    fakeApplication.applicationState = .background

    refreshScheduler.register()

    let identifier = try #require(fakeBGTaskScheduler.submissions.first?.identifier)
    let task = try #require(fakeBGTaskScheduler.launchTask(withIdentifier: identifier))
    try await fakeNetworkPathMonitor.waitForStart()
    fakeNetworkPathMonitor.update(FakeNetworkPath(isExpensive: true))

    try await Wait.until(
      { task.completionResults == [true] },
      { "Expected background refresh to complete successfully, got \(task.completionResults)" }
    )
    let requests = await session.requests
    #expect(requests == [cellularStaleSeries.podcast.feedURL.rawValue])
  }

  @Test("cellular background refreshes reach a healthy feed behind more failing feeds than fit")
  func cellularBackgroundRefreshBacksOffFailingFeeds() async throws {
    let fakeBGTaskScheduler = fakeBGTaskScheduler
    let fakeNetworkPathMonitor = fakeNetworkPathMonitor
    let session = session
    fakeNetworkPathMonitor.withholdInitialPath()
    let failingCount = 8
    for index in 0..<failingCount {
      _ = try await makeStaleSubscribedSeries(
        feedData: SyntheticFeed.rss(index: index, episodes: 1),
        feedURL: SyntheticFeed.url(index),
        lastUpdate: 10.hoursAgo
      )
      await session.respond(to: SyntheticFeed.url(index)) { url in
        (Data(), URL.response(url, statusCode: 503))
      }
    }
    let healthySeries = try await makeStaleSubscribedSeries(
      feedData: SyntheticFeed.rss(index: failingCount, episodes: 1),
      feedURL: SyntheticFeed.url(failingCount),
      lastUpdate: 5.hoursAgo
    )
    await SyntheticFeed.respond(session, episodes: 2)
    fakeApplication.applicationState = .background
    refreshScheduler.register()
    let identifier = try #require(fakeBGTaskScheduler.submissions.first?.identifier)

    let firstTask = try #require(fakeBGTaskScheduler.launchTask(withIdentifier: identifier))
    try await fakeNetworkPathMonitor.waitForStart()
    fakeNetworkPathMonitor.update(FakeNetworkPath(isExpensive: true))
    try await Wait.until(
      { firstTask.completionResults == [true] },
      { "Expected first background refresh to complete, got \(firstTask.completionResults)" }
    )
    #expect(Set(await session.requests) == Set((0..<failingCount).map(SyntheticFeed.url)))

    let secondTask = try #require(fakeBGTaskScheduler.launchTask(withIdentifier: identifier))
    try await Wait.until(
      { secondTask.completionResults == [true] },
      { "Expected second background refresh to complete, got \(secondTask.completionResults)" }
    )

    let secondRequests = await session.requests.dropFirst(failingCount)
    #expect(Array(secondRequests) == [healthySeries.podcast.feedURL.rawValue])
    #expect(try await repo.podcastSeries(healthySeries.podcast.id)?.episodes.count == 2)
  }

  private func makeStaleSubscribedSeries(
    feedData: Data = PreviewBundle.loadAsset(named: "hardfork_short", in: .FeedRSS),
    feedURL: URL = URL(string: "https://example.com/feed.rss")!,
    lastUpdate: Date = 5.hoursAgo
  ) async throws -> PodcastSeries {
    let podcastFeed = try await PodcastFeed.parse(feedData, from: FeedURL(feedURL))
    let basePodcast = try podcastFeed.toUnsavedPodcast()
    let unsavedPodcast = try Create.unsavedPodcast(
      feedURL: basePodcast.feedURL,
      title: basePodcast.title,
      image: basePodcast.image,
      description: basePodcast.description,
      link: basePodcast.link,
      lastUpdate: lastUpdate,
      subscriptionDate: Date()
    )

    return try await repo.insertSeries(
      UnsavedPodcastSeries(
        unsavedPodcast: unsavedPodcast,
        unsavedEpisodes: podcastFeed.toUnsavedEpisodes()
      )
    )
  }
}
