// Copyright Justin Bishop, 2026

import FactoryKit
import FactoryTesting
import Foundation
import Logging
import Testing

@testable import PodHaven

@Suite("of RefreshManager feed URL collision tests", .container)
actor RefreshManagerFeedURLCollisionTests {
  @DynamicInjected(\.fakeDate) private var fakeDate
  @DynamicInjected(\.podcastFeedSession) private var podcastFeedSession
  @DynamicInjected(\.refreshManager) private var refreshManager
  @DynamicInjected(\.repo) private var repo

  private var session: FakeDataFetchable { podcastFeedSession as! FakeDataFetchable }

  private static let eTag = "\"v1\""

  @Test("a feed that moves to a URL another podcast holds keeps its URL and still refreshes")
  func movedFeedKeepsItsURLWhenTheNewURLIsTaken() async throws {
    let start = Date()
    fakeDate.freeze(at: start)
    let moving =
      try await repo.insertSeries(
        UnsavedPodcastSeries(
          unsavedPodcast: try Create.unsavedPodcast(
            feedURL: FeedURL(SyntheticFeed.url(0)),
            title: "Old Title",
            lastUpdate: start.addingTimeInterval(-2 * 3600),
            subscriptionDate: start
          )
        )
      )
      .podcast
    let holder =
      try await repo.insertSeries(
        UnsavedPodcastSeries(
          unsavedPodcast: try Create.unsavedPodcast(
            feedURL: FeedURL(SyntheticFeed.movedURL(0)),
            lastUpdate: start
          )
        )
      )
      .podcast
    let feed = SyntheticFeed.rss(index: 0, episodes: 2, moved: true)
    await session.respond(toRequestsFor: SyntheticFeed.url(0)) { request in
      guard let url = request.url else { throw URLError(.badURL) }
      return (feed, URL.response(url, headerFields: ["ETag": Self.eTag]))
    }

    let captured = try await LogCapture.withSink { sink in
      try await refresh(at: start)
      try await refresh(at: start.addingTimeInterval(3600))
      return sink.captured()
    }

    let refreshed = try #require(try await repo.podcastSeries(moving.id))
    #expect(refreshed.podcast.feedURL == moving.feedURL)
    #expect(refreshed.podcast.title == SyntheticFeed.title(0))
    #expect(refreshed.episodes.count == 2)
    #expect(refreshed.podcast.lastUpdate > start)
    #expect(try await repo.podcast(holder.id)?.feedURL == holder.feedURL)
    let requests = await session.sentRequests
    #expect(requests.compactMap(\.url) == [SyntheticFeed.url(0), SyntheticFeed.url(0)])
    #expect(requests.last?.value(forHTTPHeaderField: "If-None-Match") == Self.eTag)
    let collisionLogs = captured.filter {
      $0.label == "Feed/refreshManager" && $0.message.contains("keeping its current URL")
    }
    #expect(collisionLogs.map(\.level) == [.warning])
  }

  // MARK: - Helpers

  private func refresh(at date: Date) async throws {
    fakeDate.freeze(at: date)
    try await refreshManager.performRefresh(
      trigger: .scheduled,
      stalenessThreshold: .minutes(30),
      filter: Podcast.subscribed
    )
  }
}
