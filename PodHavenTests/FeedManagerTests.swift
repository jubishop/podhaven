// Copyright Justin Bishop, 2025

import AVFoundation
import Factory
import Foundation
import Testing

@testable import PodHaven

@Suite("of FeedManager tests")
actor FeedManagerTests {
  private let session: DataFetchableMock = DataFetchableMock()
  private let repo: Repo = .empty()
  private let manager: FeedManager

  init() {
    manager = FeedManager.initForTest(session: session, repo: repo)
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

  @Test("that refreshSeries works")
  func testRefreshSeriesWorks() async throws {
    let podcastFeed = try await PodcastFeed.parse(
      Bundle.main.url(forResource: "hardfork_short", withExtension: "rss")!
    )
    let unsavedPodcast = try podcastFeed.toUnsavedPodcast()
    let podcastSeries = try await repo.insertSeries(
      unsavedPodcast,
      unsavedEpisodes: podcastFeed.episodes.map { try $0.toUnsavedEpisode() }
    )
    #expect(podcastSeries.podcast.title == "Hard Fork")
    #expect(podcastSeries.episodes.count == 2)
    #expect(
      podcastSeries.episodes.map({ $0.title }) == [
        "Our 2025 Tech Predictions and Resolutions + We Answer Your Questions",
        "The Wirecutter Show: Kitchen Gear That Lasts a Lifetime (or Extremely Close)",
      ]
    )

    let data = try Data(
      contentsOf: Bundle.main.url(forResource: "hardfork_short_updated", withExtension: "rss")!
    )
    await session.set(podcastSeries.podcast.feedURL, .data(data))
    print(podcastSeries.podcast.feedURL)
    try await manager.refreshSeries(podcastSeries: podcastSeries)

    let updatedSeries = try await repo.podcastSeries(podcastID: podcastSeries.podcast.id)!
    #expect(updatedSeries.podcast.title == "Hard Fork version 2")
    #expect(updatedSeries.episodes.count == 3)
    #expect(
      updatedSeries.episodes.map({ $0.title }) == [
        "Our 2026 Tech Predictions and Resolutions + We Answer Your Questions",
        "Gear That Lasts a Lifetime Updated",
        "Is Amazon's Drone Delivery Finally Ready for Prime Time?",
      ]
    )
  }
}
