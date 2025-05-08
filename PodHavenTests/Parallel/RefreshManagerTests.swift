// Copyright Justin Bishop, 2025

import AVFoundation
import Factory
import FactoryTesting
import Foundation
import Testing

@testable import PodHaven

@Suite("of RefreshManager tests", .container)
struct RefreshManagerTests {
  private let session: DataFetchableMock = DataFetchableMock()
  private let repo: Repo = Repo.inMemory()
  private let manager: RefreshManager

  init() {
    let repo = repo
    Container.shared.repo.register { repo }.scope(.cached)

    let feedManager = FeedManager.initForTest(session: session)
    Container.shared.feedManager.register { feedManager }.scope(.unique)

    manager = Container.shared.refreshManager()
  }

  @Test("that refreshSeries works")
  func testRefreshSeriesWorks() async throws {
    let podcastFeed = try await PodcastFeed.parse(
      FeedURL(Bundle.main.url(forResource: "hardfork_short", withExtension: "rss")!)
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
    await session.set(podcastSeries.podcast.feedURL.rawValue, .data(data))
    try await manager.refreshSeries(podcastSeries: podcastSeries)

    let updatedSeries = try await repo.podcastSeries(podcastSeries.podcast.id)!
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
