// Copyright Justin Bishop, 2025

import AVFoundation
import Factory
import Foundation
import Testing

@testable import PodHaven

@Suite("of SearchService tests")
actor SearchServiceTests {
  static private let baseURLString = "https://api.podcastindex.org/api/1.0"

  private let session: DataFetchableMock = DataFetchableMock()
  private let service: SearchService

  init() {
    service = SearchService.initForTest(session: session)
  }

  @Test("basic search query")
  func testBasicSearchQuery() async throws {
    let searchTerm = "hard fork"
    let data = try Data(
      contentsOf: Bundle.main.url(forResource: "hardfork_byterm", withExtension: "json")!
    )
    await session.set(
      URL(string: Self.baseURLString + "/search/byterm?q=\(searchTerm)")!,
      .data(data)
    )
    let result = try await service.searchByTerm(searchTerm)
    let feed = result.feeds.first!
    #expect(result.feeds.count == 5)
    #expect(feed.title == "Hard Fork")
    #expect(feed.url == URL(string: "https://feeds.simplecast.com/l2i9YnTd")!)
    #expect(feed.lastUpdateTime == Date(timeIntervalSince1970: TimeInterval(1736023489)))
    #expect(feed.categories["102"] == "Technology")
  }

  @Test("search by title")
  func testSearchByTitle() async throws {
    let searchTerm = "this is important"
    let data = try Data(
      contentsOf: Bundle.main.url(forResource: "thisisimportant_bytitle", withExtension: "json")!
    )
    await session.set(
      URL(string: Self.baseURLString + "/search/bytitle?q=\(searchTerm)")!,
      .data(data)
    )
    let result = try await service.searchByTitle(searchTerm)
    let feed = result.feeds.first!
    #expect(
      feed.description
        == "Adam Devine, Anders Holm, Blake Anderson, and Kyle Newacheck seriously discuss some very important topics."
    )
    #expect(result.feeds.count == 3)
    #expect(Set(feed.categories.values) == ["Comedy", "Society", "Culture"])
  }

  @Test("search by person")
  func testSearchByPerson() async throws {
    let searchTerm = "Neil DeGrasse Tyson"
    let data = try Data(
      contentsOf: Bundle.main.url(forResource: "ndg_byperson", withExtension: "json")!
    )
    await session.set(
      URL(string: Self.baseURLString + "/search/byperson?q=\(searchTerm)")!,
      .data(data)
    )
    let result = try await service.searchByPerson(searchTerm)
    let item = result.items.first!
    #expect(result.items.count == 60)
    #expect(
      item.title
        == "Bill Maher clashes with Neil deGrasse Tyson for refusing to admit men's sports advantage over women"
    )
    #expect(item.duration == CMTime.inSeconds(887))
  }

  @Test("search trending")
  func testSearchTrending() async throws {
    let data = try Data(
      contentsOf: Bundle.main.url(forResource: "trending", withExtension: "json")!
    )
    await session.set(
      URL(string: Self.baseURLString + "/podcasts/trending")!,
      .data(data)
    )
    let result = try await service.searchTrending()
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
    await session.set(
      URL(string: Self.baseURLString + "/podcasts/trending?cat=News")!,
      .data(data)
    )
    let result = try await service.searchTrending(categories: ["News"])
    let feed = result.feeds.first!
    #expect(result.feeds.count == 40)
    #expect(result.since == Date(timeIntervalSince1970: TimeInterval(1736208810)))
    #expect(feed.title == "Thinking Crypto News & Interviews")
  }
}
