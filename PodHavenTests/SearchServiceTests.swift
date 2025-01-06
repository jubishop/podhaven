// Copyright Justin Bishop, 2025

import Foundation
import Testing

@testable import PodHaven

@Suite("of SearchService tests")
actor SearchServiceTests {
  static private let baseURLString = "https://api.podcastindex.org/api/1.0"

  private let session: DataFetchableMock
  private let service: SearchService

  init() {
    session = DataFetchableMock()
    service = SearchService(session: session)
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
    #expect(result.count == 5)
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
    #expect(Set(feed.categories.values) == ["Comedy", "Society", "Culture"])
    #expect(result.count == 3)
  }

  @Test("listing categories")
  func testListingCategories() async throws {
    let data = try Data(
      contentsOf: Bundle.main.url(forResource: "categories", withExtension: "json")!
    )
    await session.set(
      URL(string: Self.baseURLString + "/categories/list")!,
      .data(data)
    )
    let result = try await service.listCategories()
    #expect(result.count == 112)
    #expect(result.feeds.first(where: { $0.id == 38 })!.name == "Parenting")
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
    #expect(result.count == 40)
    #expect(result.since == Date(timeIntervalSince1970: TimeInterval(1736102643)))
  }
}
