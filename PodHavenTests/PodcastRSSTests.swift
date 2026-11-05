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
      episode.enclosure?.url?.absoluteString
        == "https://op3.dev/e/https://cdn.changelog.com/uploads/friends/74/changelog--friends-74.mp3"
    )
    #expect(episode.pubDate! == Date.rfc2822.date(from: "Fri, 20 Dec 2024 20:00:00 +0000"))
    #expect(episode.iTunes.duration! == "2:08:21")
    // Episode description now uses content:encoded which has HTML formatting
    // Just verify it starts with expected HTML
    #expect(episode.description!.hasPrefix("<p>Our 7th annual year-end wrap-up"))
    #expect(episode.link?.absoluteString == "https://changelog.com/friends/74")
    #expect(
      episode.iTunes.image?.href?.absoluteString
        == "https://cdn.changelog.com/uploads/covers/changelog--friends-original.png?v=63848361609"
    )
  }

  @Test("parsing the Git News feed with date-only pubDates")
  func parseGitNewsFeedWithDateOnlyPubDates() async throws {
    let data = PreviewBundle.loadAsset(named: "git_news", in: .FeedRSS)
    let podcast = try await PodcastRSS.parse(data)
    #expect(podcast.title == "Git News AI")
    #expect(podcast.episodes.count == 3)

    let episode = podcast.episodes.first!
    #expect(episode.title == "AI Repo: HKUDS/AI-Trader")

    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(secondsFromGMT: 0)!
    let expectedPubDate = calendar.date(from: DateComponents(year: 2026, month: 7, day: 7))
    #expect(episode.pubDate == expectedPubDate)
  }

  @Test("parsing an unparseable pubDate logs a warning and yields nil")
  func parseUnparseablePubDateLogsWarning() async throws {
    let xml = """
      <?xml version="1.0"?>
      <rss xmlns:itunes="http://www.itunes.com/dtds/podcast-1.0.dtd" xmlns:atom="http://www.w3.org/2005/Atom" version="2.0">
        <channel>
          <title>Bad Dates</title>
          <description>Feed with unparseable dates</description>
          <atom:link href="https://example.com/feed.xml" rel="self" type="application/rss+xml"/>
          <itunes:image href="https://example.com/art.jpg"/>
          <item>
            <title>Episode One</title>
            <pubDate>sometime last week</pubDate>
          </item>
        </channel>
      </rss>
      """
    let podcast = try await PodcastRSS.parse(Data(xml.utf8))
    let episode = podcast.episodes.first!

    LogCapture.withSink { sink in
      #expect(episode.pubDate == nil)
      let warnings = sink.captured()
        .filter { $0.label == "Feed/podcast" && $0.message.contains("Unparseable pubDate") }
      #expect(!warnings.isEmpty)
      #expect(warnings.allSatisfy { $0.level == .warning })
    }
  }

  @Test("parsing an empty itunes:new-feed-url keeps the feed")
  func parseEmptyNewFeedURL() async throws {
    let xml = """
      <?xml version="1.0"?>
      <rss xmlns:itunes="http://www.itunes.com/dtds/podcast-1.0.dtd" xmlns:atom="http://www.w3.org/2005/Atom" version="2.0">
        <channel>
          <title>Empty New Feed URL</title>
          <description>Feed with an empty new-feed-url</description>
          <atom:link href="https://example.com/feed.xml" rel="self" type="application/rss+xml"/>
          <itunes:image href="https://example.com/art.jpg"/>
          <itunes:new-feed-url/>
          <item>
            <title>Episode One</title>
          </item>
        </channel>
      </rss>
      """
    let podcast = try await PodcastRSS.parse(Data(xml.utf8))
    #expect(podcast.title == "Empty New Feed URL")
    #expect(podcast.iTunes.newFeedURL == nil)
  }

  @Test("parsing an empty episode itunes:image href keeps the feed")
  func parseEmptyEpisodeImageHref() async throws {
    let xml = """
      <?xml version="1.0"?>
      <rss xmlns:itunes="http://www.itunes.com/dtds/podcast-1.0.dtd" xmlns:atom="http://www.w3.org/2005/Atom" version="2.0">
        <channel>
          <title>Empty Episode Image</title>
          <description>Feed with an empty episode image</description>
          <atom:link href="https://example.com/feed.xml" rel="self" type="application/rss+xml"/>
          <itunes:image href="https://example.com/art.jpg"/>
          <item>
            <title>Episode One</title>
            <enclosure url="https://example.com/one.mp3" type="audio/mpeg"/>
            <itunes:image href="https://example.com/one.jpg"/>
          </item>
          <item>
            <title>Episode Two</title>
            <enclosure url="https://example.com/two.mp3" type="audio/mpeg"/>
            <itunes:image href=""/>
          </item>
          <item>
            <title>Episode Three</title>
            <enclosure url="https://example.com/three.mp3" type="audio/mpeg"/>
            <itunes:image href="   "/>
          </item>
        </channel>
      </rss>
      """
    let podcast = try await PodcastRSS.parse(Data(xml.utf8))
    #expect(podcast.episodes.map(\.title) == ["Episode One", "Episode Two", "Episode Three"])
    #expect(podcast.episodes[0].iTunes.image?.href == URL(string: "https://example.com/one.jpg"))
    #expect(podcast.episodes[1].iTunes.image?.href == nil)
    #expect(podcast.episodes[2].iTunes.image?.href == nil)
    #expect(
      podcast.episodes[1].enclosure?.url == MediaURL(URL(string: "https://example.com/two.mp3")!)
    )
  }

  @Test("parsing an empty enclosure url keeps the feed")
  func parseEmptyEnclosureURL() async throws {
    let xml = """
      <?xml version="1.0"?>
      <rss xmlns:itunes="http://www.itunes.com/dtds/podcast-1.0.dtd" xmlns:atom="http://www.w3.org/2005/Atom" version="2.0">
        <channel>
          <title>Empty Enclosure</title>
          <description>Feed with an empty enclosure url</description>
          <atom:link href="https://example.com/feed.xml" rel="self" type="application/rss+xml"/>
          <itunes:image href="https://example.com/art.jpg"/>
          <item>
            <title>Episode One</title>
            <enclosure url="https://example.com/one.mp3" type="audio/mpeg"/>
          </item>
          <item>
            <title>Episode Two</title>
            <enclosure url="" type="audio/mpeg"/>
          </item>
          <item>
            <title>Episode Three</title>
            <enclosure url="   " type="audio/mpeg"/>
          </item>
        </channel>
      </rss>
      """
    let podcast = try await PodcastRSS.parse(Data(xml.utf8))
    #expect(podcast.episodes.map(\.title) == ["Episode One", "Episode Two", "Episode Three"])
    #expect(
      podcast.episodes[0].enclosure?.url == MediaURL(URL(string: "https://example.com/one.mp3")!)
    )
    #expect(podcast.episodes[1].enclosure?.url == nil)
    #expect(podcast.episodes[2].enclosure?.url == nil)
  }

  @Test("parsing an empty atom:link href keeps the feed")
  func parseEmptyAtomLinkHref() async throws {
    let xml = """
      <?xml version="1.0"?>
      <rss xmlns:itunes="http://www.itunes.com/dtds/podcast-1.0.dtd" xmlns:atom="http://www.w3.org/2005/Atom" version="2.0">
        <channel>
          <title>Empty Atom Link</title>
          <description>Feed with an empty atom:link href</description>
          <atom:link href="" rel="self" type="application/rss+xml"/>
          <atom:link href="" rel="hub"/>
          <atom:link href="https://example.com/feed.xml" rel="self" type="application/rss+xml"/>
          <itunes:image href="https://example.com/art.jpg"/>
          <item>
            <title>Episode One</title>
            <enclosure url="https://example.com/one.mp3" type="audio/mpeg"/>
          </item>
        </channel>
      </rss>
      """
    let podcast = try await PodcastRSS.parse(Data(xml.utf8))
    #expect(podcast.title == "Empty Atom Link")
    #expect(podcast.feedURL == FeedURL(URL(string: "https://example.com/feed.xml")!))
    #expect(podcast.episodes.map(\.title) == ["Episode One"])
  }

  @Test("parsing an atom:link without rel keeps the feed")
  func parseAtomLinkWithoutRel() async throws {
    let xml = """
      <?xml version="1.0"?>
      <rss xmlns:itunes="http://www.itunes.com/dtds/podcast-1.0.dtd" xmlns:atom="http://www.w3.org/2005/Atom" version="2.0">
        <channel>
          <title>Atom Link Without Rel</title>
          <description>Feed with an atom:link that has no rel</description>
          <atom:link href="https://example.com/alternate"/>
          <atom:link href="https://example.com/feed.xml" rel="self" type="application/rss+xml"/>
          <itunes:image href="https://example.com/art.jpg"/>
          <item>
            <title>Episode One</title>
            <enclosure url="https://example.com/one.mp3" type="audio/mpeg"/>
          </item>
        </channel>
      </rss>
      """
    let podcast = try await PodcastRSS.parse(Data(xml.utf8))
    #expect(podcast.title == "Atom Link Without Rel")
    #expect(podcast.feedURL == FeedURL(URL(string: "https://example.com/feed.xml")!))
    #expect(podcast.episodes.map(\.title) == ["Episode One"])
  }

  @Test("parsing undecodable items drops only those items and logs them once")
  func parseUndecodableItems() async throws {
    let xml = """
      <?xml version="1.0"?>
      <rss xmlns:itunes="http://www.itunes.com/dtds/podcast-1.0.dtd" version="2.0">
        <channel>
          <title>Undecodable Items</title>
          <description>Feed with items that fail to decode</description>
          <itunes:image href="https://example.com/art.jpg"/>
          <item>
            <title>Episode One</title>
            <enclosure url="https://example.com/one.mp3" type="audio/mpeg"/>
          </item>
          <item>
            <description>An item with a description and no title</description>
            <enclosure url="https://example.com/untitled.mp3" type="audio/mpeg"/>
          </item>
          <item>
            <title>Episode Three</title>
            <enclosure url="https://example.com/three.mp3" type="audio/mpeg"/>
          </item>
          <item/>
        </channel>
      </rss>
      """
    let (podcast, logs) = try await LogCapture.withSink { sink in
      let podcast = try await PodcastRSS.parse(Data(xml.utf8))
      return (podcast, sink.captured().filter { $0.message.contains("undecodable RSS items") })
    }

    #expect(podcast.title == "Undecodable Items")
    #expect(podcast.episodes.map(\.title) == ["Episode One", "Episode Three"])
    #expect(logs.count == 1)
    let log = try #require(logs.first)
    #expect(log.level == .warning)
    #expect(log.message.hasPrefix("Dropped 2 of 4 undecodable RSS items in 'Undecodable Items'"))
  }

  @Test("parsing a feed whose every item fails to decode fails")
  func parseFeedWhoseEveryItemFailsToDecode() async {
    let xml = """
      <?xml version="1.0"?>
      <rss xmlns:itunes="http://www.itunes.com/dtds/podcast-1.0.dtd" version="2.0">
        <channel>
          <title>Every Item Undecodable</title>
          <description>Feed whose items all fail to decode</description>
          <itunes:image href="https://example.com/art.jpg"/>
          <item>
            <enclosure url="https://example.com/one.mp3" type="audio/mpeg"/>
          </item>
          <item>
            <description>An item with a description and no title</description>
          </item>
        </channel>
      </rss>
      """
    await #expect(throws: DecodingError.self) {
      try await PodcastRSS.parse(Data(xml.utf8))
    }
  }

  @Test("parsing a feed with no items keeps the feed")
  func parseFeedWithNoItems() async throws {
    let xml = """
      <?xml version="1.0"?>
      <rss xmlns:itunes="http://www.itunes.com/dtds/podcast-1.0.dtd" version="2.0">
        <channel>
          <title>No Items</title>
          <description>Feed without items</description>
          <itunes:image href="https://example.com/art.jpg"/>
        </channel>
      </rss>
      """
    let podcast = try await PodcastRSS.parse(Data(xml.utf8))
    #expect(podcast.title == "No Items")
    #expect(podcast.episodes.isEmpty)
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
