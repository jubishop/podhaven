// Copyright Justin Bishop, 2026

import FactoryKit
import FactoryTesting
import Foundation
import Logging
import Testing

@testable import PodHaven

@Suite("of RefreshManager feed failure tests", .container)
actor RefreshManagerFeedFailureTests {
  @DynamicInjected(\.connectionState) private var connectionState
  @DynamicInjected(\.networkPathMonitor) private var networkPathMonitor
  @DynamicInjected(\.podcastFeedSession) private var podcastFeedSession
  @DynamicInjected(\.refreshManager) private var refreshManager
  @DynamicInjected(\.repo) private var repo

  private var fakeNetworkPathMonitor: FakeNetworkPathMonitor {
    networkPathMonitor as! FakeNetworkPathMonitor
  }
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
      try await refreshManager.performRefresh(trigger: .user, stalenessThreshold: .minutes(30))
      try await refreshManager.performRefresh(trigger: .user, stalenessThreshold: .minutes(30))
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
      try await refreshManager.performRefresh(trigger: .user, stalenessThreshold: .minutes(30))
      try await refreshManager.performRefresh(trigger: .user, stalenessThreshold: .minutes(30))
      return sink.captured()
    }

    #expect(parseFailureLevels(for: feedURL, in: captured) == [.warning, .notice])
  }

  @Test("performRefresh warns once per process for each feed over the download limit")
  func oversizedFeedsWarnOncePerFeed() async throws {
    let feedURL = try await insertPodcast(feedURL: "https://example.com/oversized.rss")
    let xml = """
      <?xml version="1.0"?>
      <rss xmlns:itunes="http://www.itunes.com/dtds/podcast-1.0.dtd" version="2.0">
        <channel>
          <title>Oversized</title>
          <description>Valid feed padded past the download limit</description>
          <itunes:image href="https://example.com/art.jpg"/>
          <item>
            <title>Episode</title>
            <guid>episode</guid>
            <enclosure url="https://example.com/episode.mp3" type="audio/mpeg"/>
          </item>
        </channel>
      </rss>
      """
    let padding = String(repeating: " ", count: PodcastFeed.downloadByteLimit)
    await session.respond(to: feedURL, data: Data((xml + padding).utf8))

    let captured = try await LogCapture.withSink { sink in
      try await refreshManager.performRefresh(trigger: .user, stalenessThreshold: .minutes(30))
      try await refreshManager.performRefresh(trigger: .user, stalenessThreshold: .minutes(30))
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
      try await refreshManager.performRefresh(trigger: .user, stalenessThreshold: .minutes(30))
      return sink.captured()
    }

    #expect(parseFailureLevels(for: offlineURL, in: captured) == [.notice])
    #expect(parseFailureLevels(for: unavailableURL, in: captured) == [.notice])
  }

  @Test("refreshSeries rethrows an HTTP error after backing off the feed")
  func refreshSeriesRethrowsHTTPError() async throws {
    let podcast = try await savedPodcast(feedURL: "https://example.com/refresh-503.rss")
    await session.respond(to: podcast.feedURL.rawValue) { url in
      (Data(), URL.response(url, statusCode: 503))
    }

    let error = await #expect(throws: HTTPStatusError.self) {
      try await refreshManager.refreshSeries(podcast: podcast)
    }

    #expect(error?.statusCode == 503)
    #expect(try await repo.podcast(podcast.id)?.refreshFailureCount == 1)
  }

  @Test("refreshSeries rethrows an unreachable feed after backing it off")
  func refreshSeriesRethrowsUnreachableFeed() async throws {
    let podcast = try await savedPodcast(feedURL: "https://example.com/refresh-dead.rss")
    await session.respond(to: podcast.feedURL.rawValue, error: URLError(.cannotFindHost))

    let error = await #expect(throws: URLError.self) {
      try await refreshManager.refreshSeries(podcast: podcast)
    }

    #expect(error?.code == .cannotFindHost)
    #expect(try await repo.podcast(podcast.id)?.refreshFailureCount == 1)
  }

  @Test("refreshSeries rethrows a feed that fails to parse after backing it off")
  func refreshSeriesRethrowsParseFailure() async throws {
    let podcast = try await savedPodcast(feedURL: "https://example.com/refresh-not-xml.rss")
    await session.respond(to: podcast.feedURL.rawValue, data: Data("Not a podcast <".utf8))

    await #expect(throws: PodcastFeedError.self) {
      try await refreshManager.refreshSeries(podcast: podcast)
    }

    #expect(try await repo.podcast(podcast.id)?.refreshFailureCount == 1)
  }

  @Test(
    "refreshSeries rethrows lost connectivity without backing off the feed",
    arguments: [URLError.Code.notConnectedToInternet, .networkConnectionLost]
  )
  func refreshSeriesRethrowsLostConnectivity(code: URLError.Code) async throws {
    let podcast = try await savedPodcast(feedURL: "https://example.com/refresh-offline.rss")
    await session.respond(to: podcast.feedURL.rawValue, error: URLError(code))

    let error = await #expect(throws: URLError.self) {
      try await refreshManager.refreshSeries(podcast: podcast)
    }

    #expect(error?.code == code)
    #expect(try await repo.podcast(podcast.id)?.refreshFailureCount == 0)
  }

  @Test("refreshSeries reports a timeout while offline as no connection without backing off")
  func refreshSeriesReportsOfflineTimeoutAsNoConnection() async throws {
    let podcast = try await savedPodcast(feedURL: "https://example.com/refresh-timeout.rss")
    await session.respond(to: podcast.feedURL.rawValue, error: URLError(.timedOut))
    _ = try await connectionState.currentPath()
    fakeNetworkPathMonitor.update(FakeNetworkPath(isSatisfied: false))

    let error = await #expect(throws: URLError.self) {
      try await refreshManager.refreshSeries(podcast: podcast)
    }

    #expect(error?.code == .notConnectedToInternet)
    #expect(try await repo.podcast(podcast.id)?.refreshFailureCount == 0)
  }

  @Test("refreshSeries doesn't throw for an unmodified feed")
  func refreshSeriesAcceptsNotModified() async throws {
    let podcast = try await savedPodcast(feedURL: SyntheticFeed.url(0).absoluteString)
    let eTag = "\"v1\""
    let feed = SyntheticFeed.rss(index: 0, episodes: 1)
    await session.respond(toRequestsFor: podcast.feedURL.rawValue) { request in
      guard let url = request.url else { throw URLError(.badURL) }
      guard request.value(forHTTPHeaderField: "If-None-Match") != eTag else {
        return (Data(), URL.response(url, statusCode: 304))
      }
      return (feed, URL.response(url, headerFields: ["ETag": eTag]))
    }
    try await refreshManager.refreshSeries(podcast: podcast)
    let refreshed = try #require(try await repo.podcast(podcast.id))

    try await refreshManager.refreshSeries(podcast: refreshed)

    #expect(await session.sentRequests.last?.value(forHTTPHeaderField: "If-None-Match") == eTag)
  }

  @Test(
    "refreshSeries doesn't throw or log an error when its podcast was deleted before the feed write"
  )
  func refreshSeriesIgnoresDeletedPodcast() async throws {
    let podcast = try await savedPodcast(feedURL: SyntheticFeed.url(0).absoluteString)
    await session.respond(
      to: podcast.feedURL.rawValue,
      data: SyntheticFeed.rss(index: 0, episodes: 1)
    )
    _ = try await repo.deletePodcast(podcast.id)

    let captured = try await LogCapture.withSink { sink in
      try await refreshManager.refreshSeries(podcast: podcast)
      return sink.captured()
    }

    let feedWriteFailureLevels =
      captured
      .filter {
        $0.label == "Feed/refreshManager"
          && $0.message.contains("Failed to update Podcast ID: \(podcast.id.rawValue)")
      }
      .map(\.level)
    #expect(feedWriteFailureLevels == [.debug])
  }

  // MARK: - Helpers

  private func insertPodcast(feedURL: String) async throws -> URL {
    try await savedPodcast(feedURL: feedURL).feedURL.rawValue
  }

  private func savedPodcast(feedURL: String) async throws -> Podcast {
    let url = try #require(URL(string: feedURL))
    let series = try await repo.insertSeries(
      UnsavedPodcastSeries(
        unsavedPodcast: try Create.unsavedPodcast(feedURL: FeedURL(url))
      )
    )
    return series.podcast
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
