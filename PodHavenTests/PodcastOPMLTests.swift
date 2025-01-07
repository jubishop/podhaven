// Copyright Justin Bishop, 2025

import Foundation
import Testing

@testable import PodHaven

@Suite("of PodcastOPML Parsing tests")
actor PodcastOPMLTests {
  @Test("parsing large OPML file")
  func parseLargeOPMLFile() async throws {
    let url = Bundle.main.url(forResource: "large", withExtension: "opml")!
    let opml = try await PodcastOPML.parse(url)
    #expect(opml.head.title == "Superphonic Podcast Subscriptions")
    #expect(opml.body.outlines.count == 48)
    #expect(opml.body.outlines.first!.text == "Chasing Life")
    #expect(
      opml.body.outlines.first!.xmlUrl.absoluteString == "https://feeds.megaphone.fm/WMHY6124370245"
    )
  }

  @Test("parsing invalid OPML file")
  func parseInvalidOPMLFile() async throws {
    let url = Bundle.main.url(forResource: "invalid", withExtension: "opml")!
    await #expect(throws: (any Error).self) { try await PodcastOPML.parse(url) }
  }
}
