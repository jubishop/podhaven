// Copyright Justin Bishop, 2025

import AVFoundation
import FactoryKit
import Foundation
import IdentifiedCollections
import Testing

@testable import PodHaven

@Suite("of PodcastFeed tests", .container)
struct PodcastFeedTests {
  @DynamicInjected(\.podcastFeedSession) private var podcastFeedSession
  @DynamicInjected(\.repo) private var repo

  private var feedSession: FakeDataFetchable { podcastFeedSession as! FakeDataFetchable }

  @Test("parsing the Pod Save America feed")
  func parsePodSaveAmericaFeed() async throws {
    let data = PreviewBundle.loadAsset(named: "pod_save_america", in: .FeedRSS)
    let fakeURL = FeedURL(URL(string: "https://example.com/feed.rss")!)
    let feed = try await PodcastFeed.parse(data, from: fakeURL)
    let unsavedPodcast = try feed.toUnsavedPodcast()
    #expect(unsavedPodcast.title == "Pod Save America")
    #expect(unsavedPodcast.link == URL(string: "https://crooked.com"))
    #expect(unsavedPodcast.image.absoluteString.contains("simplecastcdn"))
    let unsavedEpisode = feed.toUnsavedEpisodes().first!
    #expect(unsavedEpisode.duration == CMTime.seconds(2643))
  }

  @Test("parsing the Marketplace feed with an invalid MediaURL")
  func parseMarketplaceFeedWithInvalidMediaURL() async throws {
    let data = PreviewBundle.loadAsset(named: "marketplace", in: .FeedRSS)
    let feed = try await PodcastFeed.parse(data, from: FeedURL(URL.valid()))
    let unsavedPodcast = try feed.toUnsavedPodcast()
    let unsavedEpisodes = feed.toUnsavedEpisodes()
    #expect(unsavedPodcast.title == "Marketplace")
    #expect(unsavedPodcast.subscribed == false)

    // title: "What will a GOP-ruled Congress do with Trump" is removed for invalid MediaURL
    #expect(unsavedEpisodes.count == 49)
    #expect(unsavedEpisodes.first!.title == "Happy New Year! The cold weather could cost you.")
    #expect(unsavedEpisodes.last!.title == "What’s better, a pension or a 401(k)?")
  }

  @Test("parsing the Land of the Giants")
  func parseLandOfTheGiantsFeed() async throws {
    let data = PreviewBundle.loadAsset(named: "land_of_the_giants", in: .FeedRSS)
    let fakeURL = FeedURL(URL.valid())
    let feed = try await PodcastFeed.parse(data, from: fakeURL)
    let unsavedPodcast = try feed.toUnsavedPodcast()
    let unsavedEpisodes = feed.toUnsavedEpisodes()
    #expect(unsavedPodcast.title == "Land of the Giants")
    #expect(unsavedPodcast.subscribed == false)
    #expect(unsavedEpisodes.count == 71)
    #expect(unsavedEpisodes.first!.title == "Disney is a Tech Company?")
    #expect(unsavedEpisodes.last!.title == "The Rise of Amazon")
  }

  @Test("parsing the invalid Game Informer feed")
  func parseInvalidGameInformerFeed() async throws {
    let data = PreviewBundle.loadAsset(named: "game_informer_invalid", in: .FeedRSS)
    let fakeURL = FeedURL(URL.valid())
    await #expect(throws: (any Error).self) {
      try await PodcastFeed.parse(data, from: fakeURL)
    }
  }

  // This is invalid behavior by a feed but sadly dumb dumbs still do it.
  @Test("parsing the seattle official feed with duplicate guids")
  func parseSeattleOfficialFeedWithDuplicateGuids() async throws {
    let data = PreviewBundle.loadAsset(named: "seattle_official", in: .FeedRSS)
    let fakeURL = FeedURL(URL(string: "https://example.com/feed.rss")!)
    let feed = try await PodcastFeed.parse(data, from: fakeURL)
    let episodes = feed.toUnsavedEpisodes()
    let duplicatedEpisode = episodes.first(where: {
      $0.guid == GUID("178f32e0-7246-11ec-b14e-19521896ea35")
    })!
    #expect(Calendar.current.component(.year, from: duplicatedEpisode.pubDate) == 2024)
  }

  @Test("parsing the morningbrew feed with duplicate mediaURLs")
  func parseMorningBrewFeedWithDuplicateMediaURLs() async throws {
    let data = PreviewBundle.loadAsset(named: "morningbrew", in: .FeedRSS)
    let fakeURL = FeedURL(URL(string: "https://example.com/feed.rss")!)
    let feed = try await PodcastFeed.parse(data, from: fakeURL)

    let episodes = feed.toUnsavedEpisodes()
    let mediaURLs: [MediaURL: Int] = episodes.reduce(into: [:]) { counts, episode in
      counts[episode.mediaURL, default: 0] += 1
    }
    for (mediaURL, count) in mediaURLs where count > 1 {
      Issue.record("Duplicate media url found: \(mediaURL) with count: \(count)")
    }

    let episodesByMediaURL = IdentifiedArray(uniqueElements: episodes, id: \.mediaURL)
    let duplicatedEpisode = episodesByMediaURL[
      id: MediaURL(
        URL(
          string:
            "https://www.podtrac.com/pts/redirect.mp3/pdst.fm/e/tracking.swap.fm/track/bHsDpvy53mYwJpnc1UL5/traffic.megaphone.fm/MOBI2606610581.mp3?updated=1750937895"
        )!
      )
    ]!
    #expect(Calendar.current.component(.year, from: duplicatedEpisode.pubDate) == 2026)
  }

  @Test("parsing the seattlenow feed with a <p> tagged description")
  func parseSeattleNowFeedWithPTagInDescription() async throws {
    let data = PreviewBundle.loadAsset(named: "seattlenow", in: .FeedRSS)
    let fakeURL = FeedURL(URL(string: "https://example.com/feed.rss")!)
    let feed = try await PodcastFeed.parse(data, from: fakeURL)
    let unsavedPodcast = try feed.toUnsavedPodcast()
    #expect(
      unsavedPodcast.description
        == "<p>A daily news podcast for a curious city. Seattle Now brings you quick, informal, and hyper-local news updates every weekday.</p>"
    )
  }

  @Test("parsing the makingsense feed with items missing media urls")
  func parseMakingSenseFeedWithMissingMediaUrls() async throws {
    let data = PreviewBundle.loadAsset(named: "makingsense", in: .FeedRSS)
    let fakeURL = FeedURL(URL(string: "https://example.com/feed.rss")!)
    let feed = try await PodcastFeed.parse(data, from: fakeURL)
    let episodes = feed.toUnsavedEpisodes()

    // 19 episodes exist in the RSS file,
    // but the last two are dropped because they have no media URLs
    #expect(episodes.count == 17)
  }

  @Test("parsing a feed skips an empty enclosure url and keeps an empty episode image")
  func parseFeedWithEmptyEnclosureAndImageURLs() async throws {
    let xml = """
      <?xml version="1.0"?>
      <rss xmlns:itunes="http://www.itunes.com/dtds/podcast-1.0.dtd" xmlns:atom="http://www.w3.org/2005/Atom" version="2.0">
        <channel>
          <title>Empty URLs</title>
          <description>Feed with empty enclosure and image urls</description>
          <atom:link href="" rel="hub"/>
          <atom:link href="https://example.com/feed.xml" rel="self" type="application/rss+xml"/>
          <itunes:image href="https://example.com/art.jpg"/>
          <item>
            <title>Valid Episode</title>
            <guid>valid</guid>
            <enclosure url="https://example.com/valid.mp3" type="audio/mpeg"/>
            <itunes:image href="https://example.com/valid.jpg"/>
          </item>
          <item>
            <title>Empty Enclosure</title>
            <guid>empty-enclosure</guid>
            <enclosure url="" type="audio/mpeg"/>
          </item>
          <item>
            <title>Empty Image</title>
            <guid>empty-image</guid>
            <enclosure url="https://example.com/empty-image.mp3" type="audio/mpeg"/>
            <itunes:image href=""/>
          </item>
        </channel>
      </rss>
      """
    let feed = try await PodcastFeed.parse(
      Data(xml.utf8),
      from: FeedURL(URL(string: "https://example.com/other.xml")!)
    )
    #expect(feed.feedURL == FeedURL(URL(string: "https://example.com/feed.xml")!))

    let episodes = feed.toUnsavedEpisodes()
    #expect(Set(episodes.map(\.guid)) == [GUID("valid"), GUID("empty-image")])

    let validEpisode = try #require(episodes.first { $0.guid == GUID("valid") })
    #expect(validEpisode.image == URL(string: "https://example.com/valid.jpg"))

    let emptyImageEpisode = try #require(episodes.first { $0.guid == GUID("empty-image") })
    #expect(emptyImageEpisode.title == "Empty Image")
    #expect(
      emptyImageEpisode.mediaURL == MediaURL(URL(string: "https://example.com/empty-image.mp3")!)
    )
    #expect(emptyImageEpisode.image == nil)
  }

  @Test(
    "parsing a feed keeps the fetched URL when the self link isn't an absolute HTTP URL",
    arguments: ["/feed.xml", "feed://example.com/rss", "feed.xml", "//example.com/feed.xml"]
  )
  func parseFeedWithNonAbsoluteSelfLink(selfLink: String) async throws {
    let fetchedURL = FeedURL(URL(string: "https://example.com/podcast/rss")!)
    let feed = try await PodcastFeed.parse(feedData(selfLink: selfLink), from: fetchedURL)

    #expect(feed.feedURL == fetchedURL)
    #expect(try feed.toUnsavedPodcast().feedURL == fetchedURL)
    #expect(feed.toUnsavedEpisodes().map(\.guid) == [GUID("episode")])
  }

  @Test(
    "parsing a feed uses an absolute HTTP self link as HTTPS",
    arguments: [
      ("http://example.com/feed.xml", "https://example.com/feed.xml"),
      ("HTTP://example.com/feed.xml", "https://example.com/feed.xml"),
      ("https://example.com/feed.xml", "https://example.com/feed.xml"),
    ]
  )
  func parseFeedWithAbsoluteSelfLink(selfLink: String, expected: String) async throws {
    let feed = try await PodcastFeed.parse(
      feedData(selfLink: selfLink),
      from: FeedURL(URL(string: "https://example.com/podcast/rss")!)
    )

    let expectedURL = FeedURL(URL(string: expected)!)
    #expect(feed.feedURL == expectedURL)
    #expect(try feed.toUnsavedPodcast().feedURL == expectedURL)
  }

  @Test(
    "parsing a feed ignores an itunes:new-feed-url that isn't an absolute HTTP URL",
    arguments: ["/feed.xml", "feed://example.com/rss", "feed.xml", "//example.com/feed.xml"]
  )
  func parseFeedWithNonAbsoluteNewFeedURL(newFeedURL: String) async throws {
    let selfURL = FeedURL(URL(string: "https://example.com/feed.xml")!)
    let feed = try await PodcastFeed.parse(
      feedData(selfLink: selfURL.rawValue.absoluteString, newFeedURL: newFeedURL),
      from: FeedURL(URL(string: "https://example.com/podcast/rss")!)
    )

    #expect(feed.updatedFeedURL == selfURL)
    #expect(try feed.toUnsavedPodcast().feedURL == selfURL)
    #expect(feed.toUnsavedEpisodes().map(\.guid) == [GUID("episode")])
  }

  @Test("parsing a feed uses an absolute HTTP itunes:new-feed-url as HTTPS")
  func parseFeedWithAbsoluteHTTPNewFeedURL() async throws {
    let feed = try await PodcastFeed.parse(
      feedData(
        selfLink: "https://example.com/feed.xml",
        newFeedURL: "http://example.com/new.xml"
      ),
      from: FeedURL(URL(string: "https://example.com/podcast/rss")!)
    )

    let newURL = FeedURL(URL(string: "https://example.com/new.xml")!)
    #expect(feed.updatedFeedURL == newURL)
    #expect(try feed.toUnsavedPodcast().feedURL == newURL)
  }

  @Test(
    "parsing a feed resolves content URLs against the fetched URL and upgrades HTTP to HTTPS",
    arguments: [
      ("", "https://example.com/podcast/"),
      ("/", "https://example.com/"),
      ("../", "https://example.com/"),
      ("//cdn.example.com/", "https://cdn.example.com/"),
      ("http://cdn.example.com/", "https://cdn.example.com/"),
      ("HTTP://cdn.example.com/", "https://cdn.example.com/"),
      ("https://cdn.example.com/", "https://cdn.example.com/"),
      ("HTTPS://cdn.example.com/", "https://cdn.example.com/"),
    ]
  )
  func parseFeedWithContentURLs(prefix: String, expectedPrefix: String) async throws {
    let feed = try await PodcastFeed.parse(
      contentFeedData(
        podcastImage: "\(prefix)art.jpg",
        podcastLink: "\(prefix)show",
        enclosure: "\(prefix)episode.mp3",
        episodeImage: "\(prefix)episode.jpg",
        episodeLink: "\(prefix)episode",
        transcript: "\(prefix)episode.vtt"
      ),
      from: FeedURL(URL(string: "https://example.com/podcast/rss")!)
    )

    let unsavedPodcast = try feed.toUnsavedPodcast()
    #expect(unsavedPodcast.image == URL(string: "\(expectedPrefix)art.jpg"))
    #expect(unsavedPodcast.link == URL(string: "\(expectedPrefix)show"))

    let episode = try #require(feed.toUnsavedEpisodes().first)
    let mediaURL = MediaURL(URL(string: "\(expectedPrefix)episode.mp3")!)
    #expect(episode.mediaURL == mediaURL)
    #expect(episode.guid == GUID(mediaURL.rawValue.absoluteString))
    #expect(episode.image == URL(string: "\(expectedPrefix)episode.jpg"))
    #expect(episode.link == URL(string: "\(expectedPrefix)episode"))
    #expect(
      episode.publisherTranscriptReferences.map(\.url)
        == [URL(string: "\(expectedPrefix)episode.vtt")!]
    )
  }

  @Test("parsing a feed drops optional content URLs and skips enclosures that aren't HTTP")
  func parseFeedWithNonHTTPContentURLs() async throws {
    let feed = try await PodcastFeed.parse(
      contentFeedData(
        podcastImage: "https://example.com/art.jpg",
        podcastLink: "ftp://example.com/show",
        enclosure: "https://example.com/episode.mp3",
        episodeImage: "ftp://example.com/episode.jpg",
        episodeLink: "mailto:host@example.com",
        transcript: "ftp://example.com/episode.vtt",
        skippedEnclosure: "ftp://example.com/skipped.mp3"
      ),
      from: FeedURL(URL(string: "https://example.com/podcast/rss")!)
    )

    #expect(try feed.toUnsavedPodcast().link == nil)

    let episodes = feed.toUnsavedEpisodes()
    #expect(
      episodes.map(\.mediaURL) == [MediaURL(URL(string: "https://example.com/episode.mp3")!)]
    )
    let episode = try #require(episodes.first)
    #expect(episode.image == nil)
    #expect(episode.link == nil)
    #expect(episode.publisherTranscriptReferences.isEmpty)
  }

  @Test("parsing a feed rejects a podcast image that isn't HTTP")
  func parseFeedWithNonHTTPPodcastImage() async throws {
    let data = contentFeedData(
      podcastImage: "ftp://example.com/art.jpg",
      podcastLink: "https://example.com/show",
      enclosure: "https://example.com/episode.mp3",
      episodeImage: "https://example.com/episode.jpg",
      episodeLink: "https://example.com/episode",
      transcript: "https://example.com/episode.vtt"
    )

    await #expect(throws: DecodingError.self) {
      try await PodcastFeed.parse(
        data,
        from: FeedURL(URL(string: "https://example.com/podcast/rss")!)
      )
    }
  }

  @Test("parsing a feed keeps its valid episodes when an item fails to decode")
  func parseFeedWithUndecodableItem() async throws {
    let xml = """
      <?xml version="1.0"?>
      <rss xmlns:itunes="http://www.itunes.com/dtds/podcast-1.0.dtd" version="2.0">
        <channel>
          <title>Undecodable Item</title>
          <description>Feed with an item that fails to decode</description>
          <itunes:image href="https://example.com/art.jpg"/>
          <item>
            <title>Valid Episode</title>
            <guid>valid</guid>
            <enclosure url="https://example.com/valid.mp3" type="audio/mpeg"/>
          </item>
          <item>
            <guid>untitled</guid>
            <description>An item with a description and no title</description>
            <enclosure url="https://example.com/untitled.mp3" type="audio/mpeg"/>
          </item>
          <item>
            <title>Another Valid Episode</title>
            <guid>another-valid</guid>
            <enclosure url="https://example.com/another-valid.mp3" type="audio/mpeg"/>
          </item>
        </channel>
      </rss>
      """
    let feed = try await PodcastFeed.parse(
      Data(xml.utf8),
      from: FeedURL(URL(string: "https://example.com/feed.xml")!)
    )

    let episodes = feed.toUnsavedEpisodes()
    #expect(Set(episodes.map(\.guid)) == [GUID("valid"), GUID("another-valid")])
  }

  @Test(
    "parsing a feed reads itunes:duration and keeps the stored duration when it's invalid",
    arguments: [
      ("2643", 2643),
      ("2873.5", 2873.5),
      ("45:00", 2700),
      ("45:00.0", 2700),
      ("1:02:03", 3723),
      ("01:02:03.250", 3723.25),
      ("1:00:00:00", nil),
      ("abc", nil),
      ("1:ab", nil),
      ("45:", nil),
      ("", nil),
      ("-120", nil),
      ("1:-30", nil),
      ("nan", nil),
      ("inf", nil),
      ("1e400", nil),
      ("3000000000000000:00:00", nil),
    ] as [(String, Double?)]
  )
  func parseFeedWithDuration(duration: String, expectedSeconds: Double?) async throws {
    let storedDuration = CMTime.seconds(1234)
    let storedEpisode = FeedMergeEpisode(
      id: Episode.ID(rawValue: 1),
      from: try Create.unsavedEpisode(
        guid: GUID("episode"),
        mediaURL: MediaURL(URL(string: "https://example.com/episode.mp3")!),
        duration: storedDuration
      )
    )
    let feed = try await PodcastFeed.parse(
      durationFeedData(duration: duration),
      from: FeedURL(URL(string: "https://example.com/feed.xml")!)
    )

    let episode = try #require(feed.toUnsavedEpisodes(merging: [storedEpisode]).first)
    let expectedDuration =
      if let expectedSeconds { CMTime.seconds(expectedSeconds) } else { storedDuration }
    #expect(episode.duration == expectedDuration)
  }

  @Test("parsing the considerthis feed with items missing guids")
  func parseConsiderThisFeedWithMissingGuids() async throws {
    let data = PreviewBundle.loadAsset(named: "considerthis", in: .FeedRSS)
    let feed = try await PodcastFeed.parse(data, from: FeedURL(URL.valid()))
    let episodes = feed.toUnsavedEpisodes()

    // These are the mediaURLs of the two entries with no guids
    #expect(
      episodes.contains(where: {
        $0.guid
          == GUID(
            "https://chrt.fm/track/138C95/prfx.byspotify.com/e/play.podtrac.com/npr-510355/traffic.megaphone.fm/NPR8510690925.mp3?d=736&size=11791509&e=1254697878&t=podcast&p=510355"
          )
      }
      )
    )
    #expect(
      episodes.contains(where: {
        $0.guid
          == GUID(
            "https://chrt.fm/track/138C95/prfx.byspotify.com/e/play.podtrac.com/npr-510355/traffic.megaphone.fm/NPR7873235626.mp3?d=489&size=7834271&e=1254264642&t=podcast&p=510355"
          )
      }
      )
    )
  }

  @Test("parsing a feed treats empty guids as missing")
  func parseFeedWithEmptyGuids() async throws {
    let xml = """
      <?xml version="1.0"?>
      <rss xmlns:itunes="http://www.itunes.com/dtds/podcast-1.0.dtd" version="2.0">
        <channel>
          <title>Empty GUIDs</title>
          <description>Feed with empty guids</description>
          <itunes:image href="https://example.com/art.jpg"/>
          <item>
            <title>Empty</title>
            <guid></guid>
            <enclosure url="https://example.com/empty.mp3" type="audio/mpeg"/>
          </item>
          <item>
            <title>Self-closing</title>
            <guid isPermaLink="false"/>
            <enclosure url="https://example.com/self-closing.mp3" type="audio/mpeg"/>
          </item>
          <item>
            <title>Whitespace</title>
            <guid>   </guid>
            <enclosure url="https://example.com/whitespace.mp3" type="audio/mpeg"/>
          </item>
        </channel>
      </rss>
      """
    let feed = try await PodcastFeed.parse(
      Data(xml.utf8),
      from: FeedURL(URL(string: "https://example.com/feed.xml")!)
    )

    let episodes = feed.toUnsavedEpisodes()
    #expect(
      Set(episodes.map(\.guid)) == [
        GUID("https://example.com/empty.mp3"),
        GUID("https://example.com/self-closing.mp3"),
        GUID("https://example.com/whitespace.mp3"),
      ]
    )
    #expect(Set(episodes.map(\.title)) == ["Empty", "Self-closing", "Whitespace"])
  }

  @Test("parsing with invalid feedURL throws error")
  func parseWithInvalidFeedURL() async throws {
    let url = URL(string: "file://invalid.url")!

    await #expect(throws: (any Error).self) {
      try await PodcastFeed.parse(FeedURL(url))
    }
  }

  @Test("data that isn't XML fails as notXML")
  func nonXMLDataFailsAsNotXML() async throws {
    await #expect {
      try await PodcastFeed.parse(Data("Not a podcast <".utf8), from: FeedURL(URL.valid()))
    } throws: { error in
      guard case PodcastFeedError.notXML = error else { return false }
      return true
    }
  }

  @Test("a feed nested past the XML parser's depth limit fails as notXML")
  func deeplyNestedFeedFailsAsNotXML() async throws {
    let depth = 300
    let nested = String(repeating: "<x>", count: depth) + String(repeating: "</x>", count: depth)
    let xml = """
      <?xml version="1.0"?>
      <rss xmlns:itunes="http://www.itunes.com/dtds/podcast-1.0.dtd" version="2.0">
        <channel>
          <title>Nested</title>
          <description>Nested past the parser's depth limit</description>
          <itunes:image href="https://example.com/art.jpg"/>
          <item>
            <title>Episode</title>
            <guid>episode</guid>
            <enclosure url="https://example.com/episode.mp3" type="audio/mpeg"/>
            \(nested)
          </item>
        </channel>
      </rss>
      """

    await #expect {
      try await PodcastFeed.parse(Data(xml.utf8), from: FeedURL(URL.valid()))
    } throws: { error in
      guard case PodcastFeedError.notXML = error else { return false }
      return true
    }
  }

  @Test("unavailable HTTP feeds explain the failure")
  func unavailableHTTPFeedsExplainFailure() async throws {
    for statusCode in [404, 410] {
      let url = URL.valid()
      await feedSession.respond(to: url) { url in
        (Data(), URL.response(url, statusCode: statusCode))
      }

      await #expect {
        try await PodcastFeed.parse(FeedURL(url))
      } throws: { error in
        #expect(ErrorKit.message(for: error) == "This podcast's feed is no longer available.")

        guard let feedError = error as? PodcastFeedError,
          case .unavailable(let statusError) = feedError
        else { return false }

        #expect(statusError.statusCode == statusCode)
        #expect(statusError.responseURL == url)
        let loggableMessage = String(describing: ErrorKit.loggableMessage(for: error))
        #expect(loggableMessage.contains("HTTP \(statusCode)"))
        #expect(loggableMessage.contains(url.absoluteString))
        return true
      }
    }
  }

  @Test("parsing the jon_stewart feed with content:encoded priority")
  func parseJonStewartFeedWithContentEncodedPriority() async throws {
    let data = PreviewBundle.loadAsset(named: "jon_stewart", in: .FeedRSS)
    let fakeURL = FeedURL(URL(string: "https://feeds.megaphone.fm/BVLLC2163264914")!)
    let feed = try await PodcastFeed.parse(data, from: fakeURL)
    let unsavedPodcast = try feed.toUnsavedPodcast()
    let unsavedEpisode = feed.toUnsavedEpisodes().first!

    #expect(unsavedPodcast.title == "The Weekly Show with Jon Stewart")

    // Podcast description should use content:encoded (has HTML)
    #expect(unsavedPodcast.description.contains("<p>On Mondays"))

    // Episode description should use content:encoded (has HTML)
    #expect(unsavedEpisode.description!.contains("<p>As the Pentagon"))

    // Verify HTML formatting is preserved from content:encoded
    #expect(unsavedEpisode.description!.contains("<strong>"))
  }

  @Test("toUnsavedPodcast leaves freshnessCadence nil for first-time subscriptions")
  func freshnessCadenceNilOnNewSubscription() async throws {
    let data = PreviewBundle.loadAsset(named: "pod_save_america", in: .FeedRSS)
    let fakeURL = FeedURL(URL(string: "https://example.com/feed.rss")!)
    let feed = try await PodcastFeed.parse(data, from: fakeURL)
    let unsavedPodcast = try feed.toUnsavedPodcast()

    // First-time inserts go in as nil — RecommendationEngine resolves nil
    // lazily by inferring from pubDates at scoring time, so there's no need
    // to commit to a cadence at parse time.
    #expect(unsavedPodcast.freshnessCadence == nil)
  }

  @Test("toUnsavedPodcast preserves automatic transcription and cadence when merging")
  func preservesCadenceWhenMerging() async throws {
    let data = PreviewBundle.loadAsset(named: "pod_save_america", in: .FeedRSS)
    let fakeURL = FeedURL(URL(string: "https://example.com/feed.rss")!)
    let feed = try await PodcastFeed.parse(data, from: fakeURL)

    // Insert once with a user-chosen cadence, then update the cadence to
    // exercise both the explicit and nil branches of the merge path without
    // re-inserting episodes (which would collide on guid + mediaURL).
    let inserted = try await repo.insertSeries(
      UnsavedPodcastSeries(
        unsavedPodcast: try Create.unsavedPodcast(
          feedURL: fakeURL,
          title: "Pod Save America",
          alwaysTranscribeNewEpisodes: true,
          freshnessCadence: .evergreen
        ),
        unsavedEpisodes: feed.toUnsavedEpisodes()
      )
    )
    #expect(inserted.podcast.alwaysTranscribeNewEpisodes)
    #expect(inserted.podcast.freshnessCadence == .evergreen)

    let mergedEvergreen = try feed.toUnsavedPodcast(merging: inserted.podcast)
    #expect(mergedEvergreen.alwaysTranscribeNewEpisodes)
    #expect(mergedEvergreen.freshnessCadence == .evergreen)

    var clearedSettings = inserted.podcast.unsaved.settings
    clearedSettings.alwaysTranscribeNewEpisodes = false
    clearedSettings.freshnessCadence = nil
    _ = try await repo.updatePodcastSettings(inserted.podcast.id, clearedSettings)
    let refreshed = try #require(try await repo.podcastSeries(inserted.podcast.id))
    let mergedAuto = try feed.toUnsavedPodcast(merging: refreshed.podcast)
    #expect(!mergedAuto.alwaysTranscribeNewEpisodes)
    #expect(mergedAuto.freshnessCadence == nil)
  }

  @Test("parsing and inserting the twentyminutevc feed via repo")
  func parseTwentyMinuteVCFeedAndInsert() async throws {
    let data = PreviewBundle.loadAsset(named: "twentyminutevc", in: .FeedRSS)
    let fakeURL = FeedURL(URL(string: "https://thetwentyminutevc.libsyn.com/rss")!)
    let feed = try await PodcastFeed.parse(data, from: fakeURL)
    let unsavedPodcast = try feed.toUnsavedPodcast()
    let unsavedEpisodes = feed.toUnsavedEpisodes()

    #expect(
      unsavedPodcast.title
        == "The Twenty Minute VC (20VC): Venture Capital | Startup Funding | The Pitch"
    )
    #expect(unsavedEpisodes.count > 0)

    // Test inserting via repo
    // This feed has duplicate MediaURLs so this is ensuring those got deduped.
    let podcastSeries = try await repo.insertSeries(
      UnsavedPodcastSeries(
        unsavedPodcast: unsavedPodcast,
        unsavedEpisodes: unsavedEpisodes
      )
    )

    #expect(podcastSeries.podcast.title == unsavedPodcast.title)
    #expect(podcastSeries.episodes.count == unsavedEpisodes.count)
  }

  // MARK: - Helpers

  private func feedData(selfLink: String, newFeedURL: String? = nil) -> Data {
    let newFeedURLElement =
      if let newFeedURL { "<itunes:new-feed-url>\(newFeedURL)</itunes:new-feed-url>" } else { "" }
    let xml = """
      <?xml version="1.0"?>
      <rss xmlns:itunes="http://www.itunes.com/dtds/podcast-1.0.dtd" xmlns:atom="http://www.w3.org/2005/Atom" version="2.0">
        <channel>
          <title>Feed URLs</title>
          <description>Feed with a self link</description>
          <atom:link href="\(selfLink)" rel="self" type="application/rss+xml"/>
          \(newFeedURLElement)
          <itunes:image href="https://example.com/art.jpg"/>
          <item>
            <title>Episode</title>
            <guid>episode</guid>
            <enclosure url="https://example.com/episode.mp3" type="audio/mpeg"/>
          </item>
        </channel>
      </rss>
      """
    return Data(xml.utf8)
  }

  private func durationFeedData(duration: String) -> Data {
    let xml = """
      <?xml version="1.0"?>
      <rss xmlns:itunes="http://www.itunes.com/dtds/podcast-1.0.dtd" version="2.0">
        <channel>
          <title>Durations</title>
          <description>Feed with an episode duration</description>
          <itunes:image href="https://example.com/art.jpg"/>
          <item>
            <title>Episode</title>
            <guid>episode</guid>
            <enclosure url="https://example.com/episode.mp3" type="audio/mpeg"/>
            <itunes:duration>\(duration)</itunes:duration>
          </item>
        </channel>
      </rss>
      """
    return Data(xml.utf8)
  }

  private func contentFeedData(
    podcastImage: String,
    podcastLink: String,
    enclosure: String,
    episodeImage: String,
    episodeLink: String,
    transcript: String,
    skippedEnclosure: String? = nil
  ) -> Data {
    let skippedItem =
      if let skippedEnclosure {
        """
        <item>
          <title>Skipped</title>
          <enclosure url="\(skippedEnclosure)" type="audio/mpeg"/>
        </item>
        """
      } else {
        ""
      }
    let xml = """
      <?xml version="1.0"?>
      <rss xmlns:itunes="http://www.itunes.com/dtds/podcast-1.0.dtd" xmlns:podcast="https://podcastindex.org/namespace/1.0" version="2.0">
        <channel>
          <title>Content URLs</title>
          <description>Feed with content URLs</description>
          <link>\(podcastLink)</link>
          <itunes:image href="\(podcastImage)"/>
          <item>
            <title>Episode</title>
            <link>\(episodeLink)</link>
            <enclosure url="\(enclosure)" type="audio/mpeg"/>
            <itunes:image href="\(episodeImage)"/>
            <podcast:transcript url="\(transcript)" type="text/vtt"/>
          </item>
          \(skippedItem)
        </channel>
      </rss>
      """
    return Data(xml.utf8)
  }
}
