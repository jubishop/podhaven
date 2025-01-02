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
      podcast.iTunes.image.href
        == "https://cdn.changelog.com/static/images/podcasts/podcast-original-f16d0363067166f241d080ee2e2d4a28.png"
    )
    #expect(
      podcast.atomLinks.first { $0.rel == "self" }!.href == "https://changelog.com/podcast/feed"
    )
    #expect(episode.guid == "changelog.com/17/2644")
    #expect(episode.title == "State of the \"log\" 2024 (Friends)")
    #expect(
      episode.enclosure.url
        == "https://op3.dev/e/https://cdn.changelog.com/uploads/friends/74/changelog--friends-74.mp3"
    )
    #expect(episode.pubDate! == Date.rfc2822.date(from: "Fri, 20 Dec 2024 20:00:00 +0000"))
    #expect(episode.iTunes.duration! == "2:08:21")
    #expect(
      episode.description!
        == "Our 7th annual year-end wrap-up is here! We're featuring 12 listener voicemails, dope Breakmaster Cylinder remixes & our favorite episodes of the year. Thanks for listening! 💚"
    )
    #expect(episode.link == "https://changelog.com/friends/74")
    #expect(
      episode.iTunes.image!.href
        == "https://cdn.changelog.com/uploads/covers/changelog--friends-original.png?v=63848361609"
    )
  }

  @Test("parsing the Marketplace feed")
  func parseMarketplaceFeed() async throws {
    let url = Bundle.main.url(forResource: "marketplace", withExtension: "rss")!
    let podcast = try await PodcastRSS.parse(url)
    #expect(podcast.title == "Marketplace")
  }

  @Test("parsing the invalid Game Informer feed")
  func parseInvalidGameInformerFeed() async {
    let url = Bundle.main.url(forResource: "game_informer_invalid", withExtension: "rss")!
    await #expect(throws: (any Error).self) {
      try await PodcastRSS.parse(url)
    }
  }
}
