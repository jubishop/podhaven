// Copyright Justin Bishop, 2026

import FactoryKit
import FactoryTesting
import Foundation
import Testing

@testable import PodHaven

@Suite("of RefreshManager backoff tests", .container)
actor RefreshManagerBackoffTests {
  @DynamicInjected(\.fakeDate) private var fakeDate
  @DynamicInjected(\.podcastFeedSession) private var podcastFeedSession
  @DynamicInjected(\.refreshManager) private var refreshManager
  @DynamicInjected(\.repo) private var repo

  private var session: FakeDataFetchable { podcastFeedSession as! FakeDataFetchable }

  private let start = Date(
    timeIntervalSinceReferenceDate: Date().timeIntervalSinceReferenceDate.rounded(.down)
  )

  @Test("a failing feed is retried after a backoff that doubles up to a day")
  func failingFeedBacksOffExponentially() async throws {
    _ = try await insertPodcast(index: 0, lastUpdate: start.addingTimeInterval(-5 * 3600))
    await fail(index: 0)

    var attemptAt = start
    for backoffHours in [1, 2, 4, 8, 16, 24, 24] {
      let backoff = TimeInterval(backoffHours * 3600)
      #expect(try await scheduledRefreshRequests(at: attemptAt) == [SyntheticFeed.url(0)])
      #expect(try await scheduledRefreshRequests(at: attemptAt + backoff - 1).isEmpty)
      attemptAt += backoff
    }
  }

  @Test("a successful refresh, including a 304, restarts the backoff")
  func successResetsBackoff() async throws {
    _ = try await insertPodcast(index: 0, lastUpdate: start.addingTimeInterval(-5 * 3600))
    await fail(index: 0)
    #expect(try await scheduledRefreshRequests(at: start) == [SyntheticFeed.url(0)])

    await serveHonoringETag(index: 0)
    #expect(try await scheduledRefreshRequests(at: start + 3600) == [SyntheticFeed.url(0)])

    await fail(index: 0)
    #expect(try await scheduledRefreshRequests(at: start + 2 * 3600) == [SyntheticFeed.url(0)])
    #expect(try await scheduledRefreshRequests(at: start + 3 * 3600 - 1).isEmpty)
    #expect(try await scheduledRefreshRequests(at: start + 3 * 3600) == [SyntheticFeed.url(0)])

    await serveHonoringETag(index: 0)
    #expect(try await scheduledRefreshRequests(at: start + 5 * 3600) == [SyntheticFeed.url(0)])
    let revalidation = try #require(await session.sentRequests.last)
    #expect(revalidation.value(forHTTPHeaderField: "If-None-Match") == Self.eTag)

    await fail(index: 0)
    #expect(try await scheduledRefreshRequests(at: start + 6 * 3600) == [SyntheticFeed.url(0)])
    #expect(try await scheduledRefreshRequests(at: start + 7 * 3600 - 1).isEmpty)
    #expect(try await scheduledRefreshRequests(at: start + 7 * 3600) == [SyntheticFeed.url(0)])
  }

  @Test("healthy stale feeds refresh even when more feeds than the limit are failing")
  func failingFeedsDoNotTakeHealthyFeedsSlots() async throws {
    for index in 0..<3 {
      _ = try await insertPodcast(
        index: index,
        lastUpdate: start.addingTimeInterval(-10 * 3600 - TimeInterval(index * 60))
      )
      await fail(index: index)
    }
    let healthyID = try await insertPodcast(
      index: 3,
      lastUpdate: start.addingTimeInterval(-5 * 3600)
    )
    await serve(index: 3, episodes: 2)

    #expect(
      Set(try await scheduledRefreshRequests(at: start, limit: 2))
        == [SyntheticFeed.url(1), SyntheticFeed.url(2)]
    )
    #expect(
      Set(try await scheduledRefreshRequests(at: start, limit: 2))
        == [SyntheticFeed.url(0), SyntheticFeed.url(3)]
    )
    #expect(try await repo.podcastSeries(healthyID)?.episodes.count == 2)

    await serve(index: 3, episodes: 3)
    #expect(
      Set(try await scheduledRefreshRequests(at: start + 3600, limit: 2))
        == [SyntheticFeed.url(2), SyntheticFeed.url(3)]
    )
    #expect(try await repo.podcastSeries(healthyID)?.episodes.count == 3)
  }

  @Test("a user-initiated refresh ignores backoff")
  func userRefreshIgnoresBackoff() async throws {
    let podcastID = try await insertPodcast(
      index: 0,
      lastUpdate: start.addingTimeInterval(-5 * 3600)
    )
    await fail(index: 0)
    #expect(try await scheduledRefreshRequests(at: start) == [SyntheticFeed.url(0)])
    #expect(try await scheduledRefreshRequests(at: start).isEmpty)

    let requestCount = await session.requests.count
    try await refreshManager.performRefresh(
      trigger: .user,
      stalenessThreshold: .minutes(1)
    )
    let podcast = try #require(try await repo.podcast(podcastID))
    try await refreshManager.refreshSeries(podcast: podcast)

    #expect(
      Array(await session.requests.dropFirst(requestCount))
        == [SyntheticFeed.url(0), SyntheticFeed.url(0)]
    )
  }

  @Test(
    "cancellation and lost connectivity don't back off a feed",
    arguments: [
      CancellationError(),
      URLError(.cancelled),
      URLError(.notConnectedToInternet),
      URLError(.networkConnectionLost),
      URLError(.dataNotAllowed),
    ] as [any Error]
  )
  func nonFeedFailuresDoNotBackOff(error: any Error) async throws {
    _ = try await insertPodcast(index: 0, lastUpdate: start.addingTimeInterval(-5 * 3600))
    await session.respond(to: SyntheticFeed.url(0), error: error)

    #expect(try await scheduledRefreshRequests(at: start) == [SyntheticFeed.url(0)])
    #expect(try await scheduledRefreshRequests(at: start + 1) == [SyntheticFeed.url(0)])
  }

  // MARK: - Helpers

  private static let eTag = "\"v1\""

  private func insertPodcast(index: Int, lastUpdate: Date) async throws -> Podcast.ID {
    try await repo.insertSeries(
      UnsavedPodcastSeries(
        unsavedPodcast: try Create.unsavedPodcast(
          feedURL: FeedURL(SyntheticFeed.url(index)),
          lastUpdate: lastUpdate,
          subscriptionDate: start
        )
      )
    )
    .podcast.id
  }

  private func fail(index: Int) async {
    await session.respond(to: SyntheticFeed.url(index)) { url in
      (Data(), URL.response(url, statusCode: 503))
    }
  }

  private func serve(index: Int, episodes: Int) async {
    await session.respond(
      to: SyntheticFeed.url(index),
      data: SyntheticFeed.rss(index: index, episodes: episodes)
    )
  }

  private func serveHonoringETag(index: Int) async {
    let data = SyntheticFeed.rss(index: index, episodes: 1)
    await session.respond(toRequestsFor: SyntheticFeed.url(index)) { request in
      guard let url = request.url else { throw URLError(.badURL) }
      guard request.value(forHTTPHeaderField: "If-None-Match") != Self.eTag else {
        return (Data(), URL.response(url, statusCode: 304))
      }
      return (data, URL.response(url, headerFields: ["ETag": Self.eTag]))
    }
  }

  private func scheduledRefreshRequests(at date: Date, limit: Int = Int.max) async throws -> [URL] {
    fakeDate.freeze(at: date)
    let requestCount = await session.requests.count
    try await refreshManager.performRefresh(
      trigger: .scheduled,
      stalenessThreshold: .minutes(30),
      filter: Podcast.subscribed,
      limit: limit
    )
    return Array(await session.requests.dropFirst(requestCount))
  }
}
