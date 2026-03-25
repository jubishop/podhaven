// Copyright Justin Bishop, 2026

import FactoryKit
import FactoryTesting
import Foundation
import SwiftUI
import Testing
import UIKit

@testable import PodHaven

@Suite("of RefreshScheduler tests", .container)
@MainActor struct RefreshSchedulerTests {
  @DynamicInjected(\.bgTaskScheduler) private var bgTaskScheduler
  @DynamicInjected(\.podcastFeedSession) private var podcastFeedSession
  @DynamicInjected(\.refreshScheduler) private var refreshScheduler
  @DynamicInjected(\.repo) private var repo
  @DynamicInjected(\.sleeper) private var sleeper
  @DynamicInjected(\.uiApplication) private var uiApplication

  private var fakeBGTaskScheduler: FakeBGTaskScheduler {
    bgTaskScheduler as! FakeBGTaskScheduler
  }
  private var fakeApplication: FakeApplication {
    uiApplication as! FakeApplication
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
    let fakeBGTaskScheduler = fakeBGTaskScheduler
    let fakeSleeper = fakeSleeper
    let session = session
    let podcastSeries = try await makeStaleSubscribedSeries()
    let responseData = PreviewBundle.loadAsset(
      named: "hardfork_short_updated",
      in: .FeedRSS
    )
    await session.respond(to: podcastSeries.podcast.feedURL.rawValue, data: responseData)
    fakeApplication.applicationState = .active

    refreshScheduler.handleScenePhaseChange(to: .active)

    try await fakeSleeper.waitForSleepRequests(count: 1)
    await fakeSleeper.advanceTime(by: .seconds(3))
    try await Wait.until(
      { await session.requests.count == 1 },
      { "Expected the initial foreground refresh to run" }
    )
    try await fakeSleeper.waitForSleepRequests(count: 1)

    fakeApplication.applicationState = .background
    refreshScheduler.handleScenePhaseChange(to: .background)
    await fakeSleeper.advanceTime(by: .minutes(4))

    #expect(await session.requests.count == 1)
    #expect(fakeBGTaskScheduler.submissions.count == 1)
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
    let fakeApplication = fakeApplication
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
    #expect(fakeBGTaskScheduler.submissions.count == 1)
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

  private func makeStaleSubscribedSeries() async throws -> PodcastSeries {
    let feedURL = FeedURL(URL(string: "https://example.com/feed.rss")!)
    let data = PreviewBundle.loadAsset(named: "hardfork_short", in: .FeedRSS)
    let podcastFeed = try await PodcastFeed.parse(data, from: feedURL)
    let basePodcast = try podcastFeed.toUnsavedPodcast()
    let unsavedPodcast = try Create.unsavedPodcast(
      feedURL: basePodcast.feedURL,
      title: basePodcast.title,
      image: basePodcast.image,
      description: basePodcast.description,
      link: basePodcast.link,
      lastUpdate: 5.hoursAgo,
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
