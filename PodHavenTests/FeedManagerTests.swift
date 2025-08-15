// Copyright Justin Bishop, 2025

import AVFoundation
import FactoryKit
import FactoryTesting
import Foundation
import Testing

@testable import PodHaven

@Suite("of FeedManager tests", .container)
actor FeedManagerTests {
  @DynamicInjected(\.feedManagerSession) private var feedManagerSession
  @LazyInjected(\.feedManager) private var feedManager

  var session: FakeDataFetchable { feedManagerSession as! FakeDataFetchable }

  @Test("parsing the Pod Save America feed")
  func parsePodSaveAmericaFeed() async throws {
    let data = TestBundle.loadDataAsset(named: "pod_save_america", withExtension: "rss")
    let url = URL.valid()
    await session.respond(to: url, data: data)
    let feedTask = await feedManager.addURL(FeedURL(url))
    let podcastFeed = try await feedTask.feedParsed()
    let unsavedPodcast = try podcastFeed.toUnsavedPodcast()
    #expect(unsavedPodcast.title == "Pod Save America")
    #expect(unsavedPodcast.link == URL(string: "https://crooked.com"))
    #expect(unsavedPodcast.image.absoluteString.contains("simplecastcdn"))
  }

  @Test("returns true when already has URL")
  func reportsAlreadyHavingURL() async throws {
    let data = TestBundle.loadDataAsset(named: "pod_save_america", withExtension: "rss")
    let url = URL.valid()
    let feedURL = FeedURL(url)
    let asyncSemaphore = await session.waitThenRespond(to: url, data: data)
    let feedTask = await feedManager.addURL(feedURL)
    #expect(await feedManager.hasURL(feedURL))
    asyncSemaphore.signal()
    _ = try await feedTask.feedParsed()
    try await Wait.until(
      { await self.feedManager.hasURL(feedURL) == false },
      { "Feed URL still exists" }
    )
  }
}
