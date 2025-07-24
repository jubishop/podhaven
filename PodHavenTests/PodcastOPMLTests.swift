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
    let url = Bundle.main.url(forResource: "large", withExtension: "opml")!
    let opml = try await PodcastOPML.parse(try Data(contentsOf: url))
    #expect(opml.title == "Superphonic Podcast Subscriptions")
    #expect(opml.rssFeeds.count == 48)
    #expect(opml.rssFeeds.first!.title == "Chasing Life")
    #expect(
      opml.rssFeeds.first!.feedURL.absoluteString == "https://feeds.megaphone.fm/WMHY6124370245"
    )
  }

  @Test("parsing overcast exported OPML file")
  func parseOvercastExportedOPMLFile() async throws {
    let url = Bundle.main.url(forResource: "overcast", withExtension: "opml")!
    let opml = try await PodcastOPML.parse(try Data(contentsOf: url))
    #expect(opml.title == "Overcast Podcast Subscriptions")
    #expect(opml.rssFeeds.count == 43)
    #expect(opml.rssFeeds[1].title == "Techdirt")
    #expect(
      opml.rssFeeds[1].feedURL.absoluteString
        == "https://feeds.soundcloud.com/users/soundcloud:users:122508048/sounds.rss"
    )
  }

  @Test("parsing invalid OPML file")
  func parseInvalidOPMLFile() async throws {
    let url = Bundle.main.url(forResource: "invalid", withExtension: "opml")!
    await #expect(throws: ParseError.self) {
      try await PodcastOPML.parse(try Data(contentsOf: url))
    }
  }

  @Test("parsing empty OPML file")
  func parseEmptyOPMLFile() async throws {
    let url = Bundle.main.url(forResource: "empty", withExtension: "opml")!
    let opml = try await PodcastOPML.parse(try Data(contentsOf: url))
    #expect(opml.rssFeeds.isEmpty)
  }

  @Test("exporting subscribed podcasts to OPML")
  func exportSubscribedPodcasts() async throws {
    // Create test podcasts with subscription status
    _ = try await repo.insertSeries(
      try Create.unsavedPodcast(
        feedURL: FeedURL(URL(string: "https://feeds.simplecast.com/Y8lFbOT4")!),
        title: "Freakonomics Radio",
        subscriptionDate: Date()
      ),
      unsavedEpisodes: []
    )

    _ = try await repo.insertSeries(
      try Create.unsavedPodcast(
        feedURL: FeedURL(
          URL(string: "https://www.thenakedscientists.com/rss/specials_podcast.xml")!
        ),
        title: "Naked Scientists, In Short Special Editions Podcast",
        subscriptionDate: Date()
      ),
      unsavedEpisodes: []
    )

    // Create an unsubscribed podcast that should not be included
    let _ = try await repo.insertSeries(
      try Create.unsavedPodcast(
        feedURL: FeedURL(URL(string: "https://example.com/unsubscribed.xml")!),
        title: "Unsubscribed Podcast",
        subscriptionDate: nil
      ),
      unsavedEpisodes: []
    )

    // Export OPML
    let opmlData = try await PodcastOPML.exportSubscribedPodcasts()

    // Verify the exported data can be parsed back
    let opml = try await PodcastOPML.parse(opmlData)

    // Check structure
    #expect(opml.title == "PodHaven Subscriptions")
    #expect(opml.rssFeeds.count == 2)

    // Check that only subscribed podcasts are included
    let titles = Set(opml.rssFeeds.map(\.title))
    #expect(titles.contains("Freakonomics Radio"))
    #expect(titles.contains("Naked Scientists, In Short Special Editions Podcast"))
    #expect(!titles.contains("Unsubscribed Podcast"))

    // Check specific podcast details
    let freakonomicsOutline = opml.rssFeeds.first { $0.title == "Freakonomics Radio" }!
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
    #expect(opml.rssFeeds.count == 0)

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
}
