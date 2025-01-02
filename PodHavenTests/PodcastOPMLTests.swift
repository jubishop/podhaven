// Copyright Justin Bishop, 2025

import Foundation
import Testing

@testable import PodHaven

@Suite("of PodcastOPML Parsing tests")
actor PodcastOPMLTests {
  @Test("parsing large OPML file")
  func parseLargeOPMLFile() async throws {
    let url = Bundle.main.url(forResource: "large", withExtension: "opml")!
    let feeds = try await PodcastOPML.parse(url)
    #expect(feeds.count == 43)
    #expect(feeds.first!.text == "Chasing Life")
    #expect(feeds.first!.xmlUrl == "https://feeds.megaphone.fm/WMHY6124370245")
  }

  @Test("parsing invalid OPML file")
  func parseInvalidOPMLFile() async throws {
    let url = Bundle.main.url(forResource: "invalid", withExtension: "opml")!
    await #expect(throws: (any Error).self) { try await PodcastOPML.parse(url) }
  }
}
