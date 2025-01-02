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
    let episode = podcast.episodes.first!
    #expect(podcast.title == "The Changelog: Software Development, Open Source")
    let desc = "Software's best weekly news brief, deep technical interviews & talk show."
    #expect(podcast.description == desc)
    #expect(podcast.iTunes.newFeedURL == "https://changelog.com/podcast/feed")
    #expect(podcast.link == "https://changelog.com/podcast")
    #expect(
      podcast.iTunes.image
        == "https://cdn.changelog.com/static/images/podcasts/podcast-original-f16d0363067166f241d080ee2e2d4a28.png"
    )
    #expect(episode.title == "State of the \"log\" 2024 (Friends)")
    #expect(episode.pubDate == Date.rfc2822.date(from: "Fri, 20 Dec 2024 20:00:00 +0000"))
  }

  // TODO: Parse the invalid game informer feed
}
