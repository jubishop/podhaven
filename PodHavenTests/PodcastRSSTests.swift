// Copyright Justin Bishop, 2025

import Foundation
import Testing
import XMLCoder

@testable import PodHaven

@Suite("of PodcastRSS tests")
actor PodcastRSSTests {
  @Test("parsing the Changelog feed")
  func parseChangelogFeed() async throws {
    let url = Bundle.main.url(forResource: "changelog", withExtension: "rss")!
    let podcast = try await PodcastRSS.parse(url)
    #expect(podcast.title == "The Changelog: Software Development, Open Source")
    let desc = "Software's best weekly news brief, deep technical interviews & talk show."
    #expect(podcast.description == desc)
    #expect(podcast.itunesSummary == desc)
    #expect(podcast.episodes.first!.title == "State of the \"log\" 2024 (Friends)")
  }
}
