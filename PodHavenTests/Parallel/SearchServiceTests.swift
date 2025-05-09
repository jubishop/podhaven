// Copyright Justin Bishop, 2025

import AVFoundation
import Factory
import FactoryTesting
import Foundation
import Testing

@testable import PodHaven

@Suite("of SearchService tests", .container)
class SearchServiceTests {
  static private let baseURLString = "https://api.podcastindex.org/api/1.0"

  @LazyInjected(\.searchServiceSession) private var searchServiceSession
  @LazyInjected(\.searchService) private var searchService

  var session: DataFetchableMock { searchServiceSession as! DataFetchableMock }

  @Test("basic search query")
  func testBasicSearchQuery() async throws {
    let searchTerm = "hard fork"
    let data = try Data(
      contentsOf: Bundle.main.url(forResource: "hardfork_byterm", withExtension: "json")!
    )
    await session.respondWithData(
      to: URL(string: Self.baseURLString + "/search/byterm?q=\(searchTerm)")!,
      data: data
    )
    let result = try await searchService.searchByTerm(searchTerm)
    let feed = result.feeds.first!
    #expect(result.feeds.count == 5)
    #expect(feed.title == "Hard Fork")
    #expect(feed.url == FeedURL(URL(string: "https://feeds.simplecast.com/l2i9YnTd")!))
    #expect(feed.lastUpdateTime == Date(timeIntervalSince1970: TimeInterval(1736023489)))
    #expect(feed.categories!["102"] == "Technology")
  }

  @Test("search by title")
  func testSearchByTitle() async throws {
    let searchTerm = "this is important"
    let data = try Data(
      contentsOf: Bundle.main.url(forResource: "thisisimportant_bytitle", withExtension: "json")!
    )
    await session.respondWithData(
      to: URL(string: Self.baseURLString + "/search/bytitle?q=\(searchTerm)&similar=true")!,
      data: data
    )
    let result = try await searchService.searchByTitle(searchTerm)
    let feed = result.feeds.first!
    #expect(
      feed.description
        == "Adam Devine, Anders Holm, Blake Anderson, and Kyle Newacheck seriously discuss some very important topics."
    )
    #expect(result.feeds.count == 3)
    #expect(Set(feed.categories!.values) == ["Comedy", "Society", "Culture"])
  }

  @Test("search by title missing categories")
  func testSearchByTitleMissingData() async throws {
    let searchTerm = "Hello"
    let data = try Data(
      contentsOf: Bundle.main.url(forResource: "hello_bytitle", withExtension: "json")!
    )
    await session.respondWithData(
      to: URL(string: Self.baseURLString + "/search/bytitle?q=\(searchTerm)&similar=true")!,
      data: data
    )
    let result = try await searchService.searchByTitle(searchTerm)
    let feed = result.feeds[3]
    #expect(feed.description == "Xxx")
    #expect(result.feeds.count == 60)
    #expect(feed.categories == ["61": "Christianity", "65": "Religion", "66": "Spirituality"])
  }

  @Test("search by person")
  func testSearchByPerson() async throws {
    let searchTerm = "Neil DeGrasse Tyson"
    let data = try Data(
      contentsOf: Bundle.main.url(forResource: "ndg_byperson", withExtension: "json")!
    )
    await session.respondWithData(
      to: URL(string: Self.baseURLString + "/search/byperson?q=\(searchTerm)")!,
      data: data
    )
    let result = try await searchService.searchByPerson(searchTerm)
    let unsavedPodcastEpisode = try result.items.first!.toUnsavedPodcastEpisode()
    #expect(result.items.count == 60)
    #expect(
      unsavedPodcastEpisode
        == UnsavedPodcastEpisode(
          unsavedPodcast: try UnsavedPodcast(
            feedURL: FeedURL(URL(string: "https://feeds.buzzsprout.com/1733776.rss")!),
            title: "Homo Erectus Walks Amongst Us Podcast #HomoErectus",
            image: URL(string: "https://storage.buzzsprout.com/x5q2k148xhspu9dkzhvx6m7pb1ji?.jpg")!,
            description: ""
          ),
          unsavedEpisode: try UnsavedEpisode(
            guid: "Buzzsprout-16162072",
            media: MediaURL(
              URL(
                string:
                  "https://www.buzzsprout.com/1733776/episodes/16162072-bill-maher-clashes-with-neil-degrasse-tyson-for-refusing-to-admit-men-s-sports-advantage-over-women.mp3"
              )!
            ),
            title:
              "Bill Maher clashes with Neil deGrasse Tyson for refusing to admit men's sports advantage over women",
            pubDate: Date(timeIntervalSince1970: 1732406400),
            duration: CMTime.inSeconds(887),
            description:
              "<h1>Bill Maher clashes with Neil deGrasse Tyson for refusing to admit men's sports advantage over women</h1><h1>Bill Maher clashes with Neil deGrasse Tyson for refusing to admit men's sports advantage over women</h1><h1>Bill Maher clashes with Neil deGrasse Tyson for refusing to admit men's sports advantage over women</h1><p>Bill Maher clashes with Neil deGrasse Tyson for refusing to admit men's sports advantage over women<br/>Bill Maher clashes with Neil deGrasse Tyson for refusing to admit men's sports advantage over women<br/>Bill Maher clashes with Neil deGrasse Tyson for refusing to admit..."
          )
        )
    )

    #expect(throws: (any Error).self) {
      try result.items.last!.toUnsavedPodcastEpisode()
    }
  }

  @Test("search trending")
  func testSearchTrending() async throws {
    let data = try Data(
      contentsOf: Bundle.main.url(forResource: "trending", withExtension: "json")!
    )
    await session.respondWithData(
      to: URL(string: Self.baseURLString + "/podcasts/trending?lang=en")!,
      data: data
    )
    let result = try await searchService.searchTrending(language: "en")
    let feed = result.feeds.first!
    #expect(result.feeds.count == 40)
    #expect(result.since == Date(timeIntervalSince1970: TimeInterval(1736102643)))
    #expect(feed.title == "La Venganza Será Terrible (oficial)")

    let unsavedPodcast = try feed.toUnsavedPodcast()
    #expect(unsavedPodcast.lastUpdate == Date.epoch)
  }

  @Test("search trending in News category")
  func testSearchTrendingInNews() async throws {
    let data = try Data(
      contentsOf: Bundle.main.url(forResource: "trending_in_news", withExtension: "json")!
    )
    await session.respondWithData(
      to: URL(string: Self.baseURLString + "/podcasts/trending?cat=News")!,
      data: data
    )
    let result = try await searchService.searchTrending(categories: ["News"])
    let feed = result.feeds.first!
    #expect(result.feeds.count == 40)
    #expect(result.since == Date(timeIntervalSince1970: TimeInterval(1736208810)))
    #expect(feed.title == "Thinking Crypto News & Interviews")
  }

  @Test("search with failed request")
  func testSearchWithFailedRequest() async throws {
    await session.respondWithError(
      to: URL(string: Self.baseURLString + "/podcasts/trending?lang=en")!,
      error: URLError(.badServerResponse)
    )
    await #expect(throws: SearchError.self) {
      _ = try await self.searchService.searchTrending(language: "en")
    }
  }
}
