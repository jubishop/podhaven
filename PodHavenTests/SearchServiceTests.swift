// Copyright Justin Bishop, 2025

import Foundation
import Testing

@testable import PodHaven

@Suite("of SearchService tests")
actor SearchServiceTests {
  static private let baseURLString = "https://api.podcastindex.org/api/1.0"

  private let session: NetworkingMock
  private let service: SearchService

  init() {
    session = NetworkingMock()
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
    #expect(result.feeds.first!.title == "Hard Fork")
  }
}
