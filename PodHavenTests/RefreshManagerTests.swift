// Copyright Justin Bishop, 2025

import AVFoundation
import FactoryKit
import FactoryTesting
import Foundation
import Testing

@testable import PodHaven

@Suite("of RefreshManager tests", .container)
actor RefreshManagerTests {
  @DynamicInjected(\.repo) private var repo
  @DynamicInjected(\.feedManagerSession) private var feedManagerSession
  @DynamicInjected(\.refreshManager) private var refreshManager

  var session: FakeDataFetchable { feedManagerSession as! FakeDataFetchable }
  var fakeRepo: FakeRepo { repo as! FakeRepo }

  @Test("that refreshSeries works")
  func testRefreshSeriesWorks() async throws {
    let data = PreviewBundle.loadAsset(named: "hardfork_short", withExtension: "rss")
    let fakeURL = FeedURL(URL(string: "https://example.com/feed.rss")!)
    let podcastFeed = try await PodcastFeed.parse(data, from: fakeURL)
    let unsavedPodcast = try podcastFeed.toUnsavedPodcast(lastUpdate: 30.minutesAgo)
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

    let updatedData = PreviewBundle.loadAsset(
      named: "hardfork_short_updated",
      withExtension: "rss"
    )
    await session.respond(to: podcastSeries.podcast.feedURL.rawValue, data: updatedData)
    try await refreshManager.refreshSeries(podcastSeries: podcastSeries)

    let updatedSeries = try await repo.podcastSeries(podcastSeries.podcast.id)!
    #expect(updatedSeries.podcast.lastUpdate.approximatelyEquals(Date()))
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

  @Test("that refreshSeries still updates lastUpdate even when everything else is the same")
  func testRefreshSeriesWorksAlwaysUpdatesLastUpdate() async throws {
    let data = PreviewBundle.loadAsset(named: "hardfork_short", withExtension: "rss")
    let fakeURL = FeedURL(URL(string: "https://example.com/feed.rss")!)
    let podcastFeed = try await PodcastFeed.parse(data, from: fakeURL)
    let unsavedPodcast = try podcastFeed.toUnsavedPodcast(lastUpdate: 30.minutesAgo)
    let podcastSeries = try await repo.insertSeries(
      unsavedPodcast,
      unsavedEpisodes: podcastFeed.episodes.map { try $0.toUnsavedEpisode() }
    )

    let updatedData = PreviewBundle.loadAsset(named: "hardfork_short", withExtension: "rss")
    await session.respond(to: podcastSeries.podcast.feedURL.rawValue, data: updatedData)
    try await refreshManager.refreshSeries(podcastSeries: podcastSeries)

    let updatedSeries = try await repo.podcastSeries(podcastSeries.podcast.id)!
    #expect(updatedSeries.podcast.lastUpdate.approximatelyEquals(Date()))
  }

  @Test("that selective updates only update changed content")
  func testSelectiveUpdates() async throws {
    let data = PreviewBundle.loadAsset(named: "hardfork_short", withExtension: "rss")
    let fakeURL = FeedURL(URL(string: "https://example.com/feed.rss")!)
    let podcastFeed = try await PodcastFeed.parse(data, from: fakeURL)
    let unsavedPodcast = try podcastFeed.toUnsavedPodcast()
    let podcastSeries = try await repo.insertSeries(
      unsavedPodcast,
      unsavedEpisodes: podcastFeed.episodes.map { try $0.toUnsavedEpisode() }
    )

    await fakeRepo.clearAllCalls()

    let updatedData = PreviewBundle.loadAsset(
      named: "hardfork_short_updated",
      withExtension: "rss"
    )
    await session.respond(to: podcastSeries.podcast.feedURL.rawValue, data: updatedData)
    try await refreshManager.refreshSeries(podcastSeries: podcastSeries)

    let call = try await fakeRepo.expectCall(
      methodName: "updateSeriesFromFeed",
      parameters: (
        podcastID: Podcast.ID,
        podcast: Podcast?,
        unsavedEpisodes: [UnsavedEpisode],
        existingEpisodes: [Episode]
      )
      .self
    )
    #expect(call.parameters.podcast != nil)
    #expect(call.parameters.unsavedEpisodes.count == 1)
    #expect(call.parameters.existingEpisodes.count == 2)
  }

  @Test("that no repo calls occur when content is unchanged")
  func testNoRepoCallsWhenContentUnchanged() async throws {
    let data = PreviewBundle.loadAsset(named: "hardfork_short", withExtension: "rss")
    let fakeURL = FeedURL(URL(string: "https://example.com/feed.rss")!)
    let podcastFeed = try await PodcastFeed.parse(data, from: fakeURL)
    let unsavedPodcast = try podcastFeed.toUnsavedPodcast()
    let podcastSeries = try await repo.insertSeries(
      unsavedPodcast,
      unsavedEpisodes: podcastFeed.episodes.map { try $0.toUnsavedEpisode() }
    )

    await fakeRepo.clearAllCalls()

    await session.respond(to: podcastSeries.podcast.feedURL.rawValue, data: data)
    try await refreshManager.refreshSeries(podcastSeries: podcastSeries)

    try await fakeRepo.expectNoCall(methodName: "updateSeriesFromFeed")
  }

  // This is invalid behavior by a feed but sadly dumb dumbs still do it.
  @Test("that a feed can update when the guid changes with the same media")
  func testFeedUpdatesWhenGuidChangesButMediaRemainsSame() async throws {
    let data = PreviewBundle.loadAsset(named: "thisamericanlife", withExtension: "rss")
    let fakeURL = FeedURL(URL(string: "https://example.com/feed.rss")!)
    let podcastFeed = try await PodcastFeed.parse(data, from: fakeURL)
    let unsavedPodcast = try podcastFeed.toUnsavedPodcast()
    let podcastSeries = try await repo.insertSeries(
      unsavedPodcast,
      unsavedEpisodes: podcastFeed.episodes.map { try $0.toUnsavedEpisode() }
    )

    let originalEpisode = podcastSeries.episodes[id: "37163 at https://www.thisamericanlife.org"]!
    #expect(originalEpisode.title == "510: Fiasco! (2013)")

    let updatedData = PreviewBundle.loadAsset(
      named: "thisamericanlife_updated",
      withExtension: "rss"
    )
    await session.respond(to: podcastSeries.podcast.feedURL.rawValue, data: updatedData)
    try await refreshManager.refreshSeries(podcastSeries: podcastSeries)

    let updatedSeries = try await repo.podcastSeries(podcastSeries.podcast.id)!

    // Old guid that got changed
    #expect(updatedSeries.episodes[id: "37163 at https://www.thisamericanlife.org"] == nil)

    // New guid
    let updatedEpisode = updatedSeries.episodes[id: "45921 at https://www.thisamericanlife.org"]!
    #expect(
      updatedEpisode.media
        == MediaURL(
          URL(
            string:
              "https://pfx.vpixl.com/6qj4J/dts.podtrac.com/redirect.mp3/chrt.fm/track/138C95/pdst.fm/e/prefix.up.audio/s/traffic.megaphone.fm/NPR4143637574.mp3"
          )!
        )
    )
    #expect(updatedEpisode.title == "511: Fiasco! (2013)")
  }

  @Test("refreshManager ignores request for already being fetched URL")
  func refreshManagerIgnoresRequestForAlreadyBeingFetchedURL() async throws {
    let data = PreviewBundle.loadAsset(named: "hardfork_short", withExtension: "rss")
    let fakeURL = FeedURL(URL(string: "https://example.com/feed.rss")!)
    let podcastFeed = try await PodcastFeed.parse(data, from: fakeURL)
    let unsavedPodcast = try podcastFeed.toUnsavedPodcast(lastUpdate: 30.minutesAgo)
    let podcastSeries = try await repo.insertSeries(
      unsavedPodcast,
      unsavedEpisodes: podcastFeed.episodes.map { try $0.toUnsavedEpisode() }
    )

    let updatedData = PreviewBundle.loadAsset(
      named: "hardfork_short_updated",
      withExtension: "rss"
    )
    let asyncSemaphore = await session.waitThenRespond(
      to: podcastSeries.podcast.feedURL.rawValue,
      data: updatedData
    )

    Task { try await refreshManager.refreshSeries(podcastSeries: podcastSeries) }
    try await Wait.until(
      { await self.refreshManager.feedManager.hasURL(podcastSeries.podcast.feedURL) },
      { "Expected feedManager to get URL: \(podcastSeries.podcast.feedURL)" }
    )

    // The test is that this second call doesn't hang because it early exits.
    try await refreshManager.refreshSeries(podcastSeries: podcastSeries)
    asyncSemaphore.signal()
  }
}
