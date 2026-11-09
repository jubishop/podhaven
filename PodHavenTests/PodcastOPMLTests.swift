// Copyright Justin Bishop, 2025

import FactoryKit
import FactoryTesting
import Foundation
import Testing

@testable import PodHaven

@Suite("of PodcastOPML Parsing tests", .container)
struct PodcastOPMLTests {
  @DynamicInjected(\.repo) private var repo

  @Test("parsing large OPML file")
  func parseLargeOPMLFile() async throws {
    let data = PreviewBundle.loadAsset(named: "large", in: .OPML)
    let opml = try await PodcastOPML.parse(data)
    #expect(opml.title == "Superphonic Podcast Subscriptions")
    #expect(opml.rssFeeds.feeds.count == 48)
    #expect(opml.rssFeeds.skippedCount == 0)
    #expect(opml.rssFeeds.feeds.first!.title == "Chasing Life")
    #expect(
      opml.rssFeeds.feeds.first!.feedURL.absoluteString
        == "https://feeds.megaphone.fm/WMHY6124370245"
    )
  }

  @Test("parsing overcast exported OPML file")
  func parseOvercastExportedOPMLFile() async throws {
    let data = PreviewBundle.loadAsset(named: "overcast", in: .OPML)
    let opml = try await PodcastOPML.parse(data)
    #expect(opml.title == "Overcast Podcast Subscriptions")
    #expect(opml.rssFeeds.feeds.count == 43)
    #expect(opml.rssFeeds.skippedCount == 0)
    #expect(opml.rssFeeds.feeds[1].title == "Techdirt")
    #expect(
      opml.rssFeeds.feeds[1].feedURL.absoluteString
        == "https://feeds.soundcloud.com/users/soundcloud:users:122508048/sounds.rss"
    )
  }

  @Test("parsing invalid OPML file")
  func parseInvalidOPMLFile() async throws {
    let data = PreviewBundle.loadAsset(named: "invalid", in: .OPML)
    await #expect(throws: (any Error).self) {
      try await PodcastOPML.parse(data)
    }
  }

  @Test("parsing OPML with empty feed URLs keeps the valid feeds")
  func parseOPMLWithEmptyFeedURLs() async throws {
    let xml = """
      <?xml version="1.0" encoding="utf-8"?>
      <opml version="1.0">
        <head><title>Empty Feed URLs</title></head>
        <body>
          <outline text="feeds">
            <outline type="rss" text="Hard Fork" xmlUrl="https://feeds.simplecast.com/l2i9YnTd"/>
            <outline type="rss" text="Gone Podcast" xmlUrl=""/>
            <outline type="rss" text="Blank Podcast" xmlUrl="   "/>
            <outline type="rss" text="Marketplace" xmlUrl="http://www.marketplace.org/feed/podcast/marketplace"/>
            <outline type="rss" text="Another Gone Podcast" xmlUrl=""/>
          </outline>
        </body>
      </opml>
      """
    let opml = try await PodcastOPML.parse(Data(xml.utf8))
    let rssFeeds = opml.rssFeeds
    #expect(rssFeeds.feeds.map(\.title) == ["Hard Fork", "Marketplace"])
    #expect(
      rssFeeds.feeds.map(\.feedURL.absoluteString) == [
        "https://feeds.simplecast.com/l2i9YnTd",
        "https://www.marketplace.org/feed/podcast/marketplace",
      ]
    )
    #expect(rssFeeds.skippedCount == 3)
  }

  @Test("parsing OPML keeps feed URLs with uppercase schemes as HTTPS")
  func parseOPMLWithUppercaseSchemes() async throws {
    let xml = """
      <?xml version="1.0" encoding="utf-8"?>
      <opml version="1.0">
        <head><title>Uppercase Schemes</title></head>
        <body>
          <outline type="rss" text="Hard Fork" xmlUrl="HTTPS://feeds.simplecast.com/l2i9YnTd"/>
          <outline type="rss" text="Marketplace" xmlUrl="HTTP://www.marketplace.org/feed/podcast/marketplace"/>
        </body>
      </opml>
      """
    let rssFeeds = try await PodcastOPML.parse(Data(xml.utf8)).rssFeeds
    #expect(
      rssFeeds.feeds.map(\.feedURL.absoluteString) == [
        "https://feeds.simplecast.com/l2i9YnTd",
        "https://www.marketplace.org/feed/podcast/marketplace",
      ]
    )
    #expect(rssFeeds.skippedCount == 0)
  }

  @Test("parsing OPML counts feed entries without a usable feed URL")
  func parseOPMLCountsUnusableFeedURLs() async throws {
    let xml = """
      <?xml version="1.0" encoding="utf-8"?>
      <opml version="1.0">
        <head><title>Unusable Feed URLs</title></head>
        <body>
          <outline text="feeds">
            <outline type="rss" text="Hard Fork" xmlUrl="https://feeds.simplecast.com/l2i9YnTd"/>
            <outline type="rss" text="No Feed URL"/>
            <outline type="rss" text="Wrong Scheme" xmlUrl="ftp://example.com/feed.xml"/>
          </outline>
          <outline text="empty folder"/>
        </body>
      </opml>
      """
    let opml = try await PodcastOPML.parse(Data(xml.utf8))
    let rssFeeds = opml.rssFeeds
    #expect(rssFeeds.feeds.map(\.title) == ["Hard Fork"])
    #expect(rssFeeds.skippedCount == 2)
  }

  @Test("parsing empty OPML file")
  func parseEmptyOPMLFile() async throws {
    let data = PreviewBundle.loadAsset(named: "empty", in: .OPML)
    let opml = try await PodcastOPML.parse(data)
    #expect(opml.rssFeeds.feeds.isEmpty)
  }

  @Test("parsing OPML with nested folders keeps their feeds")
  func parseOPMLWithNestedFolders() async throws {
    let opml = try await PodcastOPML.parse(nestedOPML(folderDepth: 10))
    #expect(opml.rssFeeds.feeds.map(\.title) == ["Hard Fork"])
  }

  @Test("parsing deeply nested OPML fails with a user-facing error")
  func parseDeeplyNestedOPML() async throws {
    let error = try #require(
      await #expect(throws: PodcastOPMLError.self) {
        try await PodcastOPML.parse(nestedOPML(folderDepth: 200))
      }
    )
    #expect(error == .tooDeeplyNested)
    #expect(ErrorKit.message(for: error) == "This OPML file has too many nested folders to import.")
  }

  @Test("exporting subscribed podcasts to OPML")
  func exportSubscribedPodcasts() async throws {
    // Create test podcasts with subscription status
    _ = try await repo.insertSeries(
      UnsavedPodcastSeries(
        unsavedPodcast: try Create.unsavedPodcast(
          feedURL: FeedURL(URL(string: "https://feeds.simplecast.com/Y8lFbOT4")!),
          title: "Freakonomics Radio",
          subscriptionDate: Date()
        ),
        unsavedEpisodes: []
      )
    )

    _ = try await repo.insertSeries(
      UnsavedPodcastSeries(
        unsavedPodcast: try Create.unsavedPodcast(
          feedURL: FeedURL(
            URL(string: "https://www.thenakedscientists.com/rss/specials_podcast.xml")!
          ),
          title: "Naked Scientists, In Short Special Editions Podcast",
          subscriptionDate: Date()
        ),
        unsavedEpisodes: []
      )
    )

    // Create an unsubscribed podcast that should not be included
    let _ = try await repo.insertSeries(
      UnsavedPodcastSeries(
        unsavedPodcast: try Create.unsavedPodcast(
          feedURL: FeedURL(URL(string: "https://example.com/unsubscribed.xml")!),
          title: "Unsubscribed Podcast",
          subscriptionDate: nil
        ),
        unsavedEpisodes: []
      )
    )

    // Export OPML
    let opmlData = try await PodcastOPML.exportSubscribedPodcasts()

    // Verify the exported data can be parsed back
    let opml = try await PodcastOPML.parse(opmlData)

    // Check structure
    #expect(opml.title == "PodHaven Subscriptions")
    #expect(opml.rssFeeds.feeds.count == 2)

    // Check that only subscribed podcasts are included
    let titles = Set(opml.rssFeeds.feeds.map(\.title))
    #expect(titles.contains("Freakonomics Radio"))
    #expect(titles.contains("Naked Scientists, In Short Special Editions Podcast"))
    #expect(!titles.contains("Unsubscribed Podcast"))

    // Check specific podcast details
    let freakonomicsOutline = opml.rssFeeds.feeds.first { $0.title == "Freakonomics Radio" }!
    #expect(freakonomicsOutline.feedURL.absoluteString == "https://feeds.simplecast.com/Y8lFbOT4")

    // Verify XML format by checking the actual XML string
    #expect(
      String(data: opmlData, encoding: .utf8)! == """
        <?xml version="1.0" encoding="UTF-8"?>
        <opml version="2.0">
            <head>
                <title>PodHaven Subscriptions</title>
            </head>
            <body>
                <outline text="Freakonomics Radio" title="Freakonomics Radio" xmlUrl="https://feeds.simplecast.com/Y8lFbOT4" type="rss" />
                <outline text="Naked Scientists, In Short Special Editions Podcast" title="Naked Scientists, In Short Special Editions Podcast" xmlUrl="https://www.thenakedscientists.com/rss/specials_podcast.xml" type="rss" />
            </body>
        </opml>
        """
    )
  }

  @Test("export empty subscriptions")
  func exportEmptySubscriptions() async throws {
    // Ensure no subscribed podcasts exist
    let existingPodcasts = try await repo.allPodcasts(Podcast.subscribed)
    #expect(existingPodcasts.count == 0)

    // Export OPML
    let opmlData = try await PodcastOPML.exportSubscribedPodcasts()
    let opml = try await PodcastOPML.parse(opmlData)

    // Should have valid structure but no RSS feeds
    #expect(opml.title == "PodHaven Subscriptions")
    #expect(opml.rssFeeds.feeds.count == 0)

    // Verify XML format by checking the actual XML string
    #expect(
      String(data: opmlData, encoding: .utf8)! == """
        <?xml version="1.0" encoding="UTF-8"?>
        <opml version="2.0">
            <head>
                <title>PodHaven Subscriptions</title>
            </head>
            <body />
        </opml>
        """
    )
  }

  // MARK: - Helpers

  private func nestedOPML(folderDepth: Int) -> Data {
    let folders = (0..<folderDepth).map { #"<outline text="Folder \#($0)">"# }.joined()
    let closings = String(repeating: "</outline>", count: folderDepth)
    return Data(
      """
      <?xml version="1.0" encoding="UTF-8"?>
      <opml version="2.0">
      <head><title>Nested</title></head>
      <body>\(folders)<outline type="rss" text="Hard Fork" \
      xmlUrl="https://feeds.simplecast.com/l2i9YnTd"/>\(closings)</body>
      </opml>
      """
      .utf8
    )
  }
}
