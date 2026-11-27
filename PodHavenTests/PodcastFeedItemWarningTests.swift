// Copyright Justin Bishop, 2026

import Foundation
import Logging
import Testing

@testable import PodHaven

@Suite("of PodcastFeed item warning tests", .container)
struct PodcastFeedItemWarningTests {
  @Test("parsing a feed warns for only its first item problem in each process")
  func itemProblemsWarnOncePerFeed() async throws {
    let feedURL = FeedURL(URL(string: "https://example.com/item-problems.xml")!)
    let otherFeedURL = FeedURL(URL(string: "https://example.com/other-item-problems.xml")!)

    let passes = try await LogCapture.withSink { sink in
      var passes: [[LogCapture.Captured]] = []
      for url in [feedURL, feedURL, otherFeedURL] {
        let before = sink.captured().count
        let feed = try await PodcastFeed.parse(itemProblemsFeedData, from: url)
        #expect(feed.toUnsavedEpisodes().map(\.guid) == [GUID("unparseable-date")])
        passes.append(
          sink.captured().dropFirst(before)
            .filter { $0.label == "Feed/podcast" && $0.level >= .notice }
        )
      }
      return passes
    }

    let firstPass = try #require(passes.first)
    let problems = [
      "Ignoring relative feed URL: /feed.xml",
      "Dropped 1 of 4 undecodable RSS items in 'Item Problems'",
      "Invalid MediaURL: ftp://example.com/ftp.mp3 for 'FTP Enclosure'",
      "Unparseable pubDate 'sometime last week' for Unparseable Date",
    ]
    #expect(
      problems.allSatisfy { problem in firstPass.contains { $0.message.hasPrefix(problem) } }
    )
    let onePassLevels: [Logger.Level] = [.warning] + Array(repeating: .notice, count: 3)
    #expect(
      passes.map { $0.map(\.level) } == [
        onePassLevels,
        Array(repeating: .notice, count: problems.count),
        onePassLevels,
      ]
    )
  }

  // MARK: - Helpers

  private var itemProblemsFeedData: Data {
    Data(
      """
      <?xml version="1.0"?>
      <rss xmlns:itunes="http://www.itunes.com/dtds/podcast-1.0.dtd" xmlns:atom="http://www.w3.org/2005/Atom" version="2.0">
        <channel>
          <title>Item Problems</title>
          <description>Feed with problems in its items</description>
          <atom:link href="/feed.xml" rel="self" type="application/rss+xml"/>
          <itunes:image href="https://example.com/art.jpg"/>
          <item>
            <title>Unparseable Date</title>
            <guid>unparseable-date</guid>
            <pubDate>sometime last week</pubDate>
            <enclosure url="https://example.com/date.mp3" type="audio/mpeg"/>
          </item>
          <item>
            <title>FTP Enclosure</title>
            <guid>ftp-enclosure</guid>
            <enclosure url="ftp://example.com/ftp.mp3" type="audio/mpeg"/>
          </item>
          <item>
            <title>Missing Enclosure</title>
            <guid>missing-enclosure</guid>
          </item>
          <item>
            <description>An item with no title</description>
            <enclosure url="https://example.com/untitled.mp3" type="audio/mpeg"/>
          </item>
        </channel>
      </rss>
      """
      .utf8
    )
  }
}
