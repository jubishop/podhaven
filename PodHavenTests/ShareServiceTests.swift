// Copyright Justin Bishop, 2025

import FactoryKit
import FactoryTesting
import Foundation
import Testing

@testable import PodHaven

@Suite("of ShareService tests", .container)
struct ShareServiceTests {
  @DynamicInjected(\.feedManagerSession) private var feedManagerSession
  @DynamicInjected(\.repo) private var repo
  @DynamicInjected(\.shareServiceSession) private var shareServiceSession
  @DynamicInjected(\.shareService) private var shareService

  var shareSession: FakeDataFetchable { shareServiceSession as! FakeDataFetchable }
  var feedSession: FakeDataFetchable { feedManagerSession as! FakeDataFetchable }

  @Test("that a new apple podcast URL is correctly imported")
  func newApplePodcastURLImportsSuccessfully() async throws {
    let itunesData = try Data(
      contentsOf: Bundle.main.url(forResource: "lenny", withExtension: "json")!
    )
    let itunesURL = URL(string: "https://itunes.apple.com/lookup?id=1627920305&entity=podcast")!
    await shareSession.respond(to: itunesURL, data: itunesData)

    let feedData = try Data(
      contentsOf: Bundle.main.url(forResource: "lenny", withExtension: "rss")!
    )
    let feedURL = URL(string: "https://api.substack.com/feed/podcast/10845.rss")!
    await feedSession.respond(to: feedURL, data: feedData)

    try await shareService.handleIncomingURL(
      URL(
        string:
          "podhaven://share?url=https://podcasts.apple.com/us/podcast/lennys-podcast-product-growth-career/id1627920305"
      )!
    )

    let podcastSeries = try await repo.podcastSeries(FeedURL(feedURL))!
    #expect(!podcastSeries.podcast.subscribed)
    #expect(podcastSeries.podcast.title == "Lenny's Podcast: Product | Growth | Career")
    #expect(podcastSeries.episodes.count == 32)

    // TODO: Expect navigation tab is Podcasts and Path is to Lennys Podcast.
  }
}
