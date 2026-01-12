// Copyright Justin Bishop, 2025

import Foundation
import Testing
import XMLCoder

@testable import PodHaven

@Suite("of PodcastRSS tests", .container)
struct PodcastRSSTests {
  @Test("parsing the Changelog feed")
  func parseChangelogFeed() async throws {
    let data = PreviewBundle.loadAsset(named: "changelog", in: .FeedRSS)
    let podcast = try await PodcastRSS.parse(data)
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
    // Episode description now uses content:encoded which has HTML formatting
    // Just verify it starts with expected HTML
    #expect(episode.description!.hasPrefix("<p>Our 7th annual year-end wrap-up"))
    #expect(episode.link?.absoluteString == "https://changelog.com/friends/74")
    #expect(
      episode.iTunes.image!.href.absoluteString
        == "https://cdn.changelog.com/uploads/covers/changelog--friends-original.png?v=63848361609"
    )
  }

  @Test("parsing the Marketplace feed")
  func parseMarketplaceFeed() async throws {
    let data = PreviewBundle.loadAsset(named: "marketplace", in: .FeedRSS)
    let podcast = try await PodcastRSS.parse(data)
    #expect(podcast.title == "Marketplace")
  }

  @Test("parsing the Unexplainable feed")
  func parseUnexplainableFeed() async throws {
    let data = PreviewBundle.loadAsset(named: "unexplainable", in: .FeedRSS)
    let podcast = try await PodcastRSS.parse(data)
    #expect(podcast.title == "Unexplainable")
  }

  @Test("parsing TheTalkShow feed")
  func parseTheTalkShowFeed() async throws {
    let data = PreviewBundle.loadAsset(named: "thetalkshow", in: .FeedRSS)
    let podcast = try await PodcastRSS.parse(data)
    #expect(podcast.title == "The Talk Show With John Gruber")
  }

  @Test("parsing the Post Reports feed")
  func parsePostReports() async throws {
    let data = PreviewBundle.loadAsset(named: "post_reports", in: .FeedRSS)
    let podcast = try await PodcastRSS.parse(data)
    #expect(podcast.title == "Post Reports")
  }

  @Test("parsing the invalid Game Informer feed")
  func parseInvalidGameInformerFeed() async {
    let data = PreviewBundle.loadAsset(named: "game_informer_invalid", in: .FeedRSS)
    await #expect(throws: (any Error).self) {
      try await PodcastRSS.parse(data)
    }
  }

  @Test("parsing the seattle official feed with duplicate guids")
  func parseSeattleOfficialFeedWithDuplicateGuids() async throws {
    let data = PreviewBundle.loadAsset(named: "seattle_official", in: .FeedRSS)
    let podcast = try await PodcastRSS.parse(data)
    #expect(podcast.title == "Official Seattle Seahawks Podcasts")
  }

  @Test("parsing the morningbrew feed with duplicate mediaURLs")
  func parseMorningBrewFeedWithDuplicateMediaURLs() async throws {
    let data = PreviewBundle.loadAsset(named: "morningbrew", in: .FeedRSS)
    let podcast = try await PodcastRSS.parse(data)
    #expect(podcast.title == "Morning Brew Daily")
  }

  @Test("parsing the seattlenow feed with a <p> in its description")
  func parseSeattleNowFeedWithPTagInDescription() async throws {
    let data = PreviewBundle.loadAsset(named: "seattlenow", in: .FeedRSS)
    let podcast = try await PodcastRSS.parse(data)
    #expect(
      podcast.description
        == "<p>A daily news podcast for a curious city. Seattle Now brings you quick, informal, and hyper-local news updates every weekday.</p>"
    )
  }

  @Test("parsing the makingsense feed with items missing media urls")
  func parseMakingSenseFeedWithMissingMediaUrls() async throws {
    let data = PreviewBundle.loadAsset(named: "makingsense", in: .FeedRSS)
    let podcast = try await PodcastRSS.parse(data)

    // Includes the last two that have no media urls.  They will be culled by PodcastFeed.
    #expect(podcast.episodes.count == 19)
    #expect(podcast.episodes.filter { $0.enclosure?.url == nil }.count == 2)
  }

  @Test("parsing the considerthis feed with items missing guids")
  func parseConsiderThisFeedWithMissingGuids() async throws {
    let data = PreviewBundle.loadAsset(named: "considerthis", in: .FeedRSS)
    let podcast = try await PodcastRSS.parse(data)

    // Includes the two that have no guids.  They will have guids assigned by PodcastFeed.
    #expect(podcast.episodes.count == 31)
    #expect(podcast.episodes.filter { $0.guid == nil }.count == 2)
  }

  @Test("parsing the jon_stewart feed with content:encoded")
  func parseJonStewartFeedWithContentEncoded() async throws {
    let data = PreviewBundle.loadAsset(named: "jon_stewart", in: .FeedRSS)
    let podcast = try await PodcastRSS.parse(data)
    let episode = podcast.episodes.first!

    #expect(podcast.title == "The Weekly Show with Jon Stewart")

    // Podcast should use content:encoded which has HTML formatting
    #expect(podcast.description.contains("<p>On Mondays"))

    // Episode should use content:encoded which has HTML formatting
    #expect(episode.description!.contains("<p>As the Pentagon"))

    // Verify content:encoded takes priority over itunes:summary
    // (itunes:summary is plain text, content:encoded has HTML)
    #expect(episode.description != episode.iTunes.summary)
  }

  @Test("parsing the All-In feed with double-encoded ampersands")
  func parseAllInFeedWithDoubleEncodedAmpersands() async throws {
    // This feed from Libsyn contains &amp;amp; (double-encoded) which causes
    // NSXMLParser error 111 (entity ref loop) without our fix
    let data = PreviewBundle.loadAsset(named: "allin", in: .FeedRSS)
    let podcast = try await PodcastRSS.parse(data)

    #expect(podcast.title == "All-In with Chamath, Jason, Sacks & Friedberg")

    // Verify the double-encoded ampersands in episode titles are properly decoded
    // Original feed has: "Grokipedia &amp;amp; The Future" (double-encoded)
    // Should become: "Grokipedia & The Future" (single ampersand)
    let elonEpisode = podcast.episodes.first { episode in
      episode.title.contains("Elon Musk") && episode.title.contains("Grokipedia")
    }
    #expect(elonEpisode != nil)
    #expect(elonEpisode?.title.contains("Grokipedia & The Future") == true)
    #expect(elonEpisode?.title.contains("&amp;") == false)
  }
}
