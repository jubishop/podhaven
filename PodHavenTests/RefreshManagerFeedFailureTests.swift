// Copyright Justin Bishop, 2026

import FactoryKit
import FactoryTesting
import Foundation
import Logging
import Testing

@testable import PodHaven

@Suite("of RefreshManager feed failure tests", .container)
actor RefreshManagerFeedFailureTests {
  @DynamicInjected(\.podcastFeedSession) private var podcastFeedSession
  @DynamicInjected(\.refreshManager) private var refreshManager
  @DynamicInjected(\.repo) private var repo

  private var session: FakeDataFetchable {
    podcastFeedSession as! FakeDataFetchable
  }

  @Test("performRefresh warns once per process for each feed that fails to decode")
  func undecodableFeedsWarnOncePerFeed() async throws {
    let decodingURL = try await insertPodcast(feedURL: "https://example.com/not-rss.rss")
    await session.respond(
      to: decodingURL,
      data: Data("<html><body>Not a podcast</body></html>".utf8)
    )
    let notXMLURL = try await insertPodcast(feedURL: "https://example.com/not-xml.rss")
    await session.respond(to: notXMLURL, data: Data("Not a podcast <".utf8))

    let captured = try await LogCapture.withSink { sink in
      try await refreshManager.performRefresh(stalenessThreshold: .minutes(30))
      try await refreshManager.performRefresh(stalenessThreshold: .minutes(30))
      return sink.captured()
    }

    #expect(parseFailureLevels(for: decodingURL, in: captured) == [.warning, .notice])
    #expect(parseFailureLevels(for: notXMLURL, in: captured) == [.warning, .notice])
  }

  @Test("performRefresh warns once per process for a feed whose podcast image isn't HTTP")
  func nonHTTPPodcastImageWarnsOncePerFeed() async throws {
    let feedURL = try await insertPodcast(feedURL: "https://example.com/ftp-image.rss")
    let xml = """
      <?xml version="1.0"?>
      <rss xmlns:itunes="http://www.itunes.com/dtds/podcast-1.0.dtd" version="2.0">
        <channel>
          <title>FTP Image</title>
          <description>Feed with a podcast image that isn't HTTP</description>
          <itunes:image href="ftp://example.com/art.jpg"/>
          <item>
            <title>Episode</title>
            <guid>episode</guid>
            <enclosure url="https://example.com/episode.mp3" type="audio/mpeg"/>
          </item>
        </channel>
      </rss>
      """
    await session.respond(to: feedURL, data: Data(xml.utf8))

    let captured = try await LogCapture.withSink { sink in
      try await refreshManager.performRefresh(stalenessThreshold: .minutes(30))
      try await refreshManager.performRefresh(stalenessThreshold: .minutes(30))
      return sink.captured()
    }

    #expect(parseFailureLevels(for: feedURL, in: captured) == [.warning, .notice])
  }

  @Test("performRefresh keeps network and HTTP feed failures below warning")
  func networkAndHTTPFailuresStayAtNotice() async throws {
    let offlineURL = try await insertPodcast(feedURL: "https://example.com/offline.rss")
    await session.respond(to: offlineURL, error: URLError(.notConnectedToInternet))
    let unavailableURL = try await insertPodcast(feedURL: "https://example.com/unavailable.rss")
    await session.respond(to: unavailableURL) { url in
      (Data(), URL.response(url, statusCode: 503))
    }

    let captured = try await LogCapture.withSink { sink in
      try await refreshManager.performRefresh(stalenessThreshold: .minutes(30))
      return sink.captured()
    }

    #expect(parseFailureLevels(for: offlineURL, in: captured) == [.notice])
    #expect(parseFailureLevels(for: unavailableURL, in: captured) == [.notice])
  }

  // MARK: - Helpers

  private func insertPodcast(feedURL: String) async throws -> URL {
    let url = try #require(URL(string: feedURL))
    let series = try await repo.insertSeries(
      UnsavedPodcastSeries(
        unsavedPodcast: try Create.unsavedPodcast(feedURL: FeedURL(url))
      )
    )
    return series.podcast.feedURL.rawValue
  }

  private func parseFailureLevels(
    for feedURL: URL,
    in captured: [LogCapture.Captured]
  ) -> [Logging.Logger.Level] {
    captured
      .filter {
        $0.label == "Feed/refreshManager"
          && $0.message.contains("Failed to parse podcast feed")
          && $0.message.contains(feedURL.absoluteString)
      }
      .map(\.level)
  }
}
