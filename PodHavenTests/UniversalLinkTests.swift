// Copyright Justin Bishop, 2026

import FactoryKit
import FactoryTesting
import Foundation
import Testing

@testable import PodHaven

@Suite("of Universal Link tests", .container)
@MainActor struct UniversalLinkTests {
  @DynamicInjected(\.navigation) private var navigation
  @DynamicInjected(\.podcastFeedSession) private var podcastFeedSession
  @DynamicInjected(\.repo) private var repo
  @DynamicInjected(\.shareService) private var shareService

  @Test(
    "that Universal Links open an existing episode at the shared time",
    arguments: ["artisanalsoftware.com", "www.artisanalsoftware.com"],
    ["/podhaven/episode", "/podhaven/open/episode"]
  )
  func existingEpisode(host: String, path: String) async throws {
    let feedURL = URL(string: "https://api.substack.com/feed/podcast/10845.rss")!
    let feedData = PreviewBundle.loadAsset(named: "lenny", in: .FeedRSS)
    let podcastFeed = try await PodcastFeed.parse(feedData, from: FeedURL(feedURL))
    try await repo.insertSeries(podcastFeed.toUnsavedSeries())
    var components = URLComponents(string: "https://\(host)\(path)")!
    components.queryItems = [
      URLQueryItem(name: "feedURL", value: feedURL.absoluteString),
      URLQueryItem(name: "guid", value: "substack:post:167485876"),
      URLQueryItem(name: "startTime", value: "90"),
    ]
    let url = components.url!

    #expect(ShareService.isShareURL(url))
    try await shareService.handleIncomingURL(url)

    #expect(navigation.currentTab == .podcasts)
    guard case .episode(let episode, let startTime) = navigation.podcasts.path[safe: 2] else {
      Issue.record("Expected navigation to the shared episode")
      return
    }
    #expect(episode.mediaGUID.guid.rawValue == "substack:post:167485876")
    #expect(startTime == 90)
  }

  @Test(
    "that Universal Links preview an unsubscribed podcast without saving it",
    arguments: ["artisanalsoftware.com", "www.artisanalsoftware.com"]
  )
  func newPodcast(host: String) async throws {
    let feedURL = URL(string: "https://api.substack.com/feed/podcast/10845.rss")!
    let feedData = PreviewBundle.loadAsset(named: "lenny", in: .FeedRSS)
    let session = podcastFeedSession as! FakeDataFetchable
    await session.respond(to: feedURL, data: feedData)
    var components = URLComponents(string: "https://\(host)/podhaven/open/podcast")!
    components.queryItems = [URLQueryItem(name: "feedURL", value: feedURL.absoluteString)]

    try await shareService.handleIncomingURL(components.url!)

    let feed = try await PodcastFeed.parse(feedData, from: FeedURL(feedURL))
    #expect(navigation.currentTab == .search)
    #expect(navigation.search.path == [.unsavedPodcastSeries(try feed.toUnsavedSeries())])
    #expect(try await repo.allPodcasts(AppDB.noOp).isEmpty)
  }

  @Test(
    "that malformed or unrelated Universal Links are rejected",
    arguments: [
      "https://example.com/podhaven/podcast?feedURL=https://example.com/feed",
      "https://artisanalsoftware.com.evil.example/podhaven/podcast?feedURL=https://example.com/feed",
      "http://artisanalsoftware.com/podhaven/podcast?feedURL=https://example.com/feed",
      "https://artisanalsoftware.com/podhaven/privacy?feedURL=https://example.com/feed",
      "https://artisanalsoftware.com/podhaven/open/podcast",
      "https://artisanalsoftware.com/podhaven/open/podcast?feedURL=file:///tmp/test.opml",
      "https://artisanalsoftware.com/podhaven/open/podcast?feedURL=relative/path",
      "https://artisanalsoftware.com/podhaven/open/podcast?feedURL=https://example.com/a&feedURL=https://example.com/b",
      "https://artisanalsoftware.com/podhaven/open/episode?feedURL=https://example.com/feed",
      "https://artisanalsoftware.com/podhaven/open/episode?feedURL=https://example.com/feed&guid=",
      "https://artisanalsoftware.com/podhaven/open/episode?feedURL=https://example.com/feed&guid=a&guid=b",
    ]
  )
  func rejectInvalidURL(value: String) async {
    let url = URL(string: value)!
    #expect(!ShareService.isShareURL(url))
    await #expect(throws: URLError.self) {
      try await shareService.handleIncomingURL(url)
    }
  }
}
