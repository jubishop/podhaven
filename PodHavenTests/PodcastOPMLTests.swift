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
    await #expect(throws: ParseError.self) {
      try await PodcastOPML.parse(try Data(contentsOf: url))
    }
  }

  @Test("parsing empty OPML file")
  func parseEmptyOPMLFile() async throws {
    let url = Bundle.main.url(forResource: "empty", withExtension: "opml")!
    let opml = try await PodcastOPML.parse(try Data(contentsOf: url))
    #expect(opml.body.outlines.isEmpty)
  }

  @Test("exporting subscribed podcasts to OPML")
  func exportSubscribedPodcasts() async throws {
    // Create test podcasts with subscription status
    _ = try await repo.insertSeries(
      try Create.unsavedPodcast(
        feedURL: FeedURL(URL(string: "https://feeds.simplecast.com/Y8lFbOT4")!),
        title: "Freakonomics Radio",
        subscribed: true
      ),
      unsavedEpisodes: []
    )

    _ = try await repo.insertSeries(
      try Create.unsavedPodcast(
        feedURL: FeedURL(
          URL(string: "https://www.thenakedscientists.com/rss/specials_podcast.xml")!
        ),
        title: "Naked Scientists, In Short Special Editions Podcast",
        subscribed: true
      ),
      unsavedEpisodes: []
    )

    // Create an unsubscribed podcast that should not be included
    let _ = try await repo.insertSeries(
      try Create.unsavedPodcast(
        feedURL: FeedURL(URL(string: "https://example.com/unsubscribed.xml")!),
        title: "Unsubscribed Podcast",
        subscribed: false
      ),
      unsavedEpisodes: []
    )

    // Export OPML
    let opmlData = try await PodcastOPML.exportSubscribedPodcasts()

    // Verify the exported data can be parsed back
    let opml = try await PodcastOPML.parse(opmlData)

    // Check structure
    #expect(opml.head.title == "PodHaven Subscriptions")
    #expect(opml.body.outlines.count == 2)

    // Check that only subscribed podcasts are included
    let titles = Set(opml.body.outlines.map(\.text))
    #expect(titles.contains("Freakonomics Radio"))
    #expect(titles.contains("Naked Scientists, In Short Special Editions Podcast"))
    #expect(!titles.contains("Unsubscribed Podcast"))

    // Check specific podcast details
    let freakonomicsOutline = opml.body.outlines.first { $0.text == "Freakonomics Radio" }!
    #expect(freakonomicsOutline.type == "rss")
    #expect(freakonomicsOutline.xmlUrl.absoluteString == "https://feeds.simplecast.com/Y8lFbOT4")

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

    // Should have valid structure but no outlines
    #expect(opml.head.title == "PodHaven Subscriptions")
    #expect(opml.body.outlines.count == 0)

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
