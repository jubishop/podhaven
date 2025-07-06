// Copyright Justin Bishop, 2025

import AVFoundation
import FactoryKit
import FactoryTesting
import Foundation
import Testing

@testable import PodHaven

@Suite("of RefreshManager tests", .container)
class RefreshManagerTests {
  @DynamicInjected(\.repo) private var repo
  @DynamicInjected(\.feedManagerSession) private var feedManagerSession
  @DynamicInjected(\.refreshManager) private var refreshManager

  var session: FakeDataFetchable { feedManagerSession as! FakeDataFetchable }
  var fakeRepo: FakeRepo { repo as! FakeRepo }

  @Test("that refreshSeries works")
  func testRefreshSeriesWorks() async throws {
    let url = Bundle.main.url(forResource: "hardfork_short", withExtension: "rss")!
    let podcastFeed = try await PodcastFeed.parse(try Data(contentsOf: url), from: FeedURL(url))
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
    await session.respond(to: podcastSeries.podcast.feedURL.rawValue, data: data)
    try await refreshManager.refreshSeries(podcastSeries: podcastSeries)

    let updatedSeries = try await repo.podcastSeries(podcastSeries.podcast.id)!
    #expect(
      updatedSeries.podcast.feedURL
        == FeedURL(URL(string: "https://feeds.simplecast.com/l2i9YnTdNEW")!)
    )
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

  @Test("that selective updates only update changed content")
  func testSelectiveUpdates() async throws {
    let url = Bundle.main.url(forResource: "hardfork_short", withExtension: "rss")!
    let podcastFeed = try await PodcastFeed.parse(try Data(contentsOf: url), from: FeedURL(url))
    let unsavedPodcast = try podcastFeed.toUnsavedPodcast()
    let podcastSeries = try await repo.insertSeries(
      unsavedPodcast,
      unsavedEpisodes: podcastFeed.episodes.map { try $0.toUnsavedEpisode() }
    )

    await fakeRepo.clearAllCalls()

    let updatedData = try Data(
      contentsOf: Bundle.main.url(forResource: "hardfork_short_updated", withExtension: "rss")!
    )
    await session.respond(to: podcastSeries.podcast.feedURL.rawValue, data: updatedData)
    try await refreshManager.refreshSeries(podcastSeries: podcastSeries)

    let call = try await fakeRepo.expectCall(FakeRepo.UpdateSeriesFromFeedCall.self)
    #expect(call.parameters.podcast != nil)
    #expect(call.parameters.unsavedEpisodes.count == 1)
    #expect(call.parameters.existingEpisodes.count == 2)
  }

  @Test("that no repo calls occur when content is unchanged")
  func testNoRepoCallsWhenContentUnchanged() async throws {
    let url = Bundle.main.url(forResource: "hardfork_short", withExtension: "rss")!
    let podcastFeed = try await PodcastFeed.parse(try Data(contentsOf: url), from: FeedURL(url))
    let unsavedPodcast = try podcastFeed.toUnsavedPodcast()
    let podcastSeries = try await repo.insertSeries(
      unsavedPodcast,
      unsavedEpisodes: podcastFeed.episodes.map { try $0.toUnsavedEpisode() }
    )

    await fakeRepo.clearAllCalls()

    let sameData = try Data(contentsOf: url)
    await session.respond(to: podcastSeries.podcast.feedURL.rawValue, data: sameData)
    try await refreshManager.refreshSeries(podcastSeries: podcastSeries)

    try await fakeRepo.expectNoCall(FakeRepo.UpdateSeriesFromFeedCall.self)
  }
}
