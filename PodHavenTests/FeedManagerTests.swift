// Copyright Justin Bishop, 2025

import AVFoundation
import Factory
import Foundation
import Testing

@testable import PodHaven

@Suite("of FeedManager tests")
actor FeedManagerTests {
  private let session: DataFetchableMock
  private let manager: FeedManager

  init() {
    session = DataFetchableMock()
    manager = FeedManager.initForTest(session: session)
    Container.shared.feedManager.context(.test) { self.manager }
    Container.shared.repo.context(.test) { Repo.empty() }
  }

  @Test("parsing the Pod Save America feed")
  func parsePodSaveAmericaFeed() async throws {
    let data = try Data(
      contentsOf: Bundle.main.url(forResource: "pod_save_america", withExtension: "rss")!
    )
    let url = URL.valid()
    await session.set(url, .data(data))
    let feedTask = await manager.addURL(url)
    let feedResult = await feedTask.feedParsed()
    let feed = feedResult.isSuccessfulWith()!
    let unsavedPodcast = try feed.toUnsavedPodcast()
    #expect(unsavedPodcast.title == "Pod Save America")
    #expect(unsavedPodcast.link == URL(string: "https://crooked.com"))
    #expect(unsavedPodcast.image.absoluteString.contains("simplecastcdn") != nil)
  }

  // TODO: Test FeedManager.refreshSeries

  @Test("that refreshSeries works")
  func refreshSeries() async throws {
    
  }
}
