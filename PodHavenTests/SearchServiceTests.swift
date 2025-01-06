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
      contentsOf: Bundle.main.url(forResource: "hardfork", withExtension: "json")!
    )
    await session.set(
      URL(string: Self.baseURLString + "/search/byterm?q=\(searchTerm)")!,
      .data(data)
    )
    let result = try await service.searchByTerm(searchTerm)
    let feed = result.feeds.first!
    #expect(feed.title == "Hard Fork")
    #expect(feed.url == URL(string: "https://feeds.simplecast.com/l2i9YnTd")!)
    #expect(feed.lastUpdateTime == Date(timeIntervalSince1970: TimeInterval(1736023489)))
    #expect(feed.categories["102"] == "Technology")
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
}
