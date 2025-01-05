// Copyright Justin Bishop, 2025

import Foundation
import Testing

@testable import PodHaven

@Suite("of SearchService tests")
actor SearchServiceTests {
  @Test("basic search query")
  func testBasicSearchQuery() async throws {
    let result = try await SearchService.searchByTerm("hard fork")
    print(String(data: result, encoding: .utf8)!)
  }
}

