// Copyright Justin Bishop, 2025

import FactoryKit
import FactoryTesting
import Foundation
import Testing

@testable import PodHaven

@Suite("of ShareService tests", .container)
@MainActor class ShareServiceTests {
  @DynamicInjected(\.feedManagerSession) private var feedManagerSession
  @DynamicInjected(\.navigation) private var navigation
  @DynamicInjected(\.repo) private var repo
  @DynamicInjected(\.shareServiceSession) private var shareServiceSession
  @DynamicInjected(\.shareService) private var shareService

  var shareSession: FakeDataFetchable { shareServiceSession as! FakeDataFetchable }
  var feedSession: FakeDataFetchable { feedManagerSession as! FakeDataFetchable }

  @Test("that a new apple podcast URL is correctly imported")
  func newApplePodcastURLImportsSuccessfully() async throws {
    #expect(try await repo.allPodcasts().isEmpty)

    let itunesData = try Data(
      contentsOf: Bundle.main.url(forResource: "lenny", withExtension: "json")!
    )
    let itunesID: String = "1627920305"
    await shareSession.respond(
      to: ShareHelpers.itunesLookupURL(for: itunesID),
      data: itunesData
    )

    let feedData = try Data(
      contentsOf: Bundle.main.url(forResource: "lenny", withExtension: "rss")!
    )
    let feedURL = URL(string: "https://api.substack.com/feed/podcast/10845.rss")!
    await feedSession.respond(to: feedURL, data: feedData)

    try await shareService.handleIncomingURL(
      ShareHelpers.shareURL(
        with: ShareHelpers.itunesURL(
          for: itunesID,
          withTitle: "Lenny's Podcast: Product | Growth | Career"
        )
      )
    )

    let podcastSeries = try await repo.podcastSeries(FeedURL(feedURL))!
    #expect(!podcastSeries.podcast.subscribed)
    #expect(podcastSeries.podcast.title == "Lenny's Podcast: Product | Growth | Career")
    #expect(podcastSeries.episodes.count == 32)

    #expect(navigation.currentTab == .podcasts)
    #expect(
      navigation.podcasts.path == [.viewType(.unsubscribed), .podcast(podcastSeries.podcast)]
    )
  }

  @Test(
    "that an existing apple podcast URL is shown correctly",
    arguments: [false, true]  // podcast.subscribed
  )
  func existingApplePodcastURLShowsSuccessfully(subscribed: Bool) async throws {
    let feedURL = URL(string: "https://api.substack.com/feed/podcast/10845.rss")!
    try await repo.insertSeries(
      Create.unsavedPodcast(
        feedURL: FeedURL(feedURL),
        subscribed: subscribed
      )
    )
    #expect(try await repo.allPodcasts().count == 1)

    let itunesData = try Data(
      contentsOf: Bundle.main.url(forResource: "lenny", withExtension: "json")!
    )
    let itunesID: String = "1627920305"
    await shareSession.respond(
      to: ShareHelpers.itunesLookupURL(for: itunesID),
      data: itunesData
    )

    let feedData = try Data(
      contentsOf: Bundle.main.url(forResource: "lenny", withExtension: "rss")!
    )
    await feedSession.respond(to: feedURL, data: feedData)

    try await shareService.handleIncomingURL(
      ShareHelpers.shareURL(
        with: ShareHelpers.itunesURL(
          for: itunesID,
          withTitle: "Lenny's Podcast: Product | Growth | Career"
        )
      )
    )

    #expect(try await repo.allPodcasts().count == 1)
    let podcastSeries = try await repo.podcastSeries(FeedURL(feedURL))!
    #expect(podcastSeries.podcast.subscribed == subscribed)
    #expect(podcastSeries.podcast.title == "Lenny's Podcast: Product | Growth | Career")
    #expect(podcastSeries.episodes.count == 32)

    #expect(navigation.currentTab == .podcasts)
    #expect(
      navigation.podcasts.path == [
        .viewType(subscribed ? .subscribed : .unsubscribed), .podcast(podcastSeries.podcast),
      ]
    )
  }
}
