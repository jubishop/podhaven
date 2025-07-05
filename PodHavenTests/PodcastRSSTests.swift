// Copyright Justin Bishop, 2025

import Foundation
import Testing
import XMLCoder

@testable import PodHaven

@Suite("of PodcastRSS tests")
struct PodcastRSSTests {
  @Test("parsing the Changelog feed")
  func parseChangelogFeed() async throws {
    let url = Bundle.main.url(forResource: "changelog", withExtension: "rss")!
    let podcast = try await PodcastRSS.parse(try Data(contentsOf: url))
    let episode = podcast.episodes.first!
    #expect(podcast.title == "The Changelog: Software Development, Open Source")
    let desc = "Software's best weekly news brief, deep technical interviews & talk show."
    #expect(podcast.description == desc)
    #expect(podcast.iTunes.newFeedURL?.absoluteString == "https://changelog.com/podcast/feed")
    #expect(podcast.link?.absoluteString == "https://changelog.com/podcast")
    #expect(
      podcast.iTunes.image.href.absoluteString
        == "https://cdn.changelog.com/static/images/podcasts/podcast-original-f16d0363067166f241d080ee2e2d4a28.png"
    )
    #expect(podcast.feedURL?.absoluteString == "https://changelog.com/podcast/feed")
    #expect(episode.guid == "changelog.com/17/2644")
    #expect(episode.title == "State of the \"log\" 2024 (Friends)")
    #expect(
      episode.enclosure?.url.absoluteString
        == "https://op3.dev/e/https://cdn.changelog.com/uploads/friends/74/changelog--friends-74.mp3"
    )
    #expect(episode.pubDate! == Date.rfc2822.date(from: "Fri, 20 Dec 2024 20:00:00 +0000"))
    #expect(episode.iTunes.duration! == "2:08:21")
    #expect(
      episode.description!
        == "Our 7th annual year-end wrap-up is here! We're featuring 12 listener voicemails, dope Breakmaster Cylinder remixes & our favorite episodes of the year. Thanks for listening! 💚"
    )
    #expect(episode.link?.absoluteString == "https://changelog.com/friends/74")
    #expect(
      episode.iTunes.image!.href.absoluteString
        == "https://cdn.changelog.com/uploads/covers/changelog--friends-original.png?v=63848361609"
    )
  }

  @Test("parsing the Marketplace feed")
  func parseMarketplaceFeed() async throws {
    let url = Bundle.main.url(forResource: "marketplace", withExtension: "rss")!
    let podcast = try await PodcastRSS.parse(try Data(contentsOf: url))
    #expect(podcast.title == "Marketplace")
  }

  @Test("parsing the Unexplainable feed")
  func parseUnexplainableFeed() async throws {
    let url = Bundle.main.url(forResource: "unexplainable", withExtension: "rss")!
    let podcast = try await PodcastRSS.parse(try Data(contentsOf: url))
    #expect(podcast.title == "Unexplainable")
  }

  @Test("parsing TheTalkShow feed")
  func parseTheTalkShowFeed() async throws {
    let url = Bundle.main.url(forResource: "thetalkshow", withExtension: "rss")!
    let podcast = try await PodcastRSS.parse(try Data(contentsOf: url))
    #expect(podcast.title == "The Talk Show With John Gruber")
  }

  @Test("parsing the invalid Game Informer feed")
  func parseInvalidGameInformerFeed() async {
    let url = Bundle.main.url(forResource: "game_informer_invalid", withExtension: "rss")!
    await #expect(throws: (any Error).self) {
      try await PodcastRSS.parse(try Data(contentsOf: url))
    }
  }

  @Test("parsing the seattle official feed with duplicate guids")
  func parseSeattleOfficialFeedWithDuplicateGuids() async throws {
    let url = Bundle.main.url(forResource: "seattle_official", withExtension: "rss")!
    let podcast = try await PodcastRSS.parse(try Data(contentsOf: url))
    #expect(podcast.title == "Official Seattle Seahawks Podcasts")
  }

  @Test("parsing the morningbrew feed with duplicate mediaURLs")
  func parseMorningBrewFeedWithDuplicateMediaURLs() async throws {
    let url = Bundle.main.url(forResource: "morningbrew", withExtension: "rss")!
    let podcast = try await PodcastRSS.parse(try Data(contentsOf: url))
    #expect(podcast.title == "Morning Brew Daily")
  }

  @Test("parsing the seattlenow feed with a <p> in its description")
  func parseSeattleNowFeedWithPTagInDescription() async throws {
    let url = Bundle.main.url(forResource: "seattlenow", withExtension: "rss")!
    let podcast = try await PodcastRSS.parse(try Data(contentsOf: url))
    #expect(
      podcast.description
        == "<p>A daily news podcast for a curious city. Seattle Now brings you quick, informal, and hyper-local news updates every weekday.</p>"
    )
  }

  @Test("parsing the makingsense feed with items missing media urls")
  func parseMakingSenseFeedWithMissingMediaUrls() async throws {
    let url = Bundle.main.url(forResource: "makingsense", withExtension: "rss")!
    let podcast = try await PodcastRSS.parse(try Data(contentsOf: url))

    // Includes the last two that have no media urls.  They will be culled by PodcastFeed.
    #expect(podcast.episodes.count == 19)
  }
}
