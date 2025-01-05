// Copyright Justin Bishop, 2025

import Foundation
import Testing

@testable import PodHaven

@Suite("of SearchService tests")
actor SearchServiceTests {
  private let service: SearchService

  init() {
    service = SearchService(session: URLSession.shared)
  }

  @Test("basic search query")
  func testBasicSearchQuery() async throws {
    let result = try await service.searchByTerm("hard fork")
    #expect(result.feeds.first!.title == "Hard Fork")
  }
}

