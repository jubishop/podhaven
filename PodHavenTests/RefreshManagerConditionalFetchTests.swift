// Copyright Justin Bishop, 2026

import FactoryKit
import FactoryTesting
import Foundation
import GRDB
import Testing

@testable import PodHaven

@Suite("of RefreshManager conditional fetch tests", .container)
actor RefreshManagerConditionalFetchTests {
  @DynamicInjected(\.appDB) private var appDB
  @DynamicInjected(\.podcastFeedSession) private var podcastFeedSession
  @DynamicInjected(\.refreshManager) private var refreshManager
  @DynamicInjected(\.repo) private var repo

  private var session: FakeDataFetchable { podcastFeedSession as! FakeDataFetchable }
  private var fakeRepo: FakeRepo { repo as! FakeRepo }

  private static let lastModified = "Wed, 21 Oct 2026 07:28:00 GMT"

  @Test("a 304 response advances lastUpdate without parsing the feed")
  func notModifiedAdvancesLastUpdateWithoutParsing() async throws {
    let podcastID = try await insertSeries(index: 0)
    await serve(index: 0, eTag: "\"v1\"", episodes: 1)
    try await refreshStale(podcastID)
    fakeRepo.clearAllCalls()

    try await refreshStale(podcastID)

    let request = try #require(await session.sentRequests.last)
    #expect(request.value(forHTTPHeaderField: "If-None-Match") == "\"v1\"")
    #expect(request.value(forHTTPHeaderField: "If-Modified-Since") == Self.lastModified)
    #expect(request.cachePolicy == .reloadIgnoringLocalCacheData)
    try fakeRepo.expectNoCall(methodName: "feedMergeEpisodes")
    #expect(try await podcast(podcastID).lastUpdate > 1.hoursAgo)

    try await refreshStale(podcastID)

    #expect(await lastIfNoneMatch() == "\"v1\"")
  }

  @Test("a changed feed is applied and its validators are sent on the next refresh")
  func changedFeedIsAppliedAndItsValidatorsAreSentNext() async throws {
    let podcastID = try await insertSeries(index: 1)
    await serve(index: 1, eTag: "\"v1\"", episodes: 1)
    try await refreshStale(podcastID)
    await serve(index: 1, eTag: "\"v2\"", episodes: 2)

    try await refreshStale(podcastID)

    #expect(await lastIfNoneMatch() == "\"v1\"")
    #expect(try await repo.podcastSeries(podcastID)?.episodes.count == 2)

    try await refreshStale(podcastID)

    #expect(await lastIfNoneMatch() == "\"v2\"")
  }

  @Test("validators stored by another build are not sent")
  func otherBuildValidatorsAreNotSent() async throws {
    let podcastID = try await insertSeries(index: 2)
    await serve(index: 2, eTag: "\"v1\"", episodes: 1)
    try await refreshStale(podcastID)
    _ = try await appDB.unsafeTestDB.write { db in
      try Podcast.withID(podcastID)
        .updateAll(db, Podcast.Columns.feedValidatorsBuild.set(to: "older build"))
    }
    fakeRepo.clearAllCalls()

    try await refreshStale(podcastID)

    let request = try #require(await session.sentRequests.last)
    #expect(request.value(forHTTPHeaderField: "If-None-Match") == nil)
    #expect(request.value(forHTTPHeaderField: "If-Modified-Since") == nil)
    _ = try fakeRepo.expectCalls(methodName: "feedMergeEpisodes")

    try await refreshStale(podcastID)

    #expect(await lastIfNoneMatch() == "\"v1\"")
  }

  @Test("a feed that fails to parse is downloaded in full next time")
  func unparseableFeedIsNotRevalidated() async throws {
    let podcastID = try await insertSeries(index: 3)
    await session.respond(to: SyntheticFeed.url(3)) { url in
      (
        Data("<html><body>Not a podcast</body></html>".utf8),
        URL.response(url, headerFields: ["ETag": "\"html\""])
      )
    }
    try await refreshStale(podcastID)
    await serve(index: 3, eTag: "\"html\"", episodes: 1)

    try await refreshStale(podcastID)

    #expect(await lastIfNoneMatch() == nil)
    #expect(try await podcast(podcastID).lastUpdate > 1.hoursAgo)
  }

  @Test("a moved feed is fetched from its new URL without the old validators")
  func movedFeedDropsValidators() async throws {
    let podcastID = try await insertSeries(index: 4)
    await serve(index: 4, eTag: "\"v1\"", episodes: 1, moved: true)
    try await refreshStale(podcastID)
    #expect(try await podcast(podcastID).feedURL.rawValue == SyntheticFeed.movedURL(4))
    await serve(index: 4, eTag: "\"v1\"", episodes: 1, moved: true, at: SyntheticFeed.movedURL(4))

    try await refreshStale(podcastID)

    let request = try #require(await session.sentRequests.last)
    #expect(request.url == SyntheticFeed.movedURL(4))
    #expect(request.value(forHTTPHeaderField: "If-None-Match") == nil)
  }

  // MARK: - Helpers

  private func insertSeries(index: Int) async throws -> Podcast.ID {
    let feed = try await PodcastFeed.parse(
      SyntheticFeed.rss(index: index, episodes: 1),
      from: FeedURL(SyntheticFeed.url(index))
    )
    return
      try await repo.insertSeries(
        UnsavedPodcastSeries(
          unsavedPodcast: try feed.toUnsavedPodcast(),
          unsavedEpisodes: feed.toUnsavedEpisodes()
        )
      )
      .podcast.id
  }

  // Answers like a server that honors If-None-Match for the current eTag.
  private func serve(
    index: Int,
    eTag: String,
    episodes: Int,
    moved: Bool = false,
    at url: URL? = nil
  ) async {
    let data = SyntheticFeed.rss(index: index, episodes: episodes, moved: moved)
    await session.respond(toRequestsFor: url ?? SyntheticFeed.url(index)) { request in
      guard let requestURL = request.url else { throw URLError(.badURL) }
      guard request.value(forHTTPHeaderField: "If-None-Match") != eTag else {
        return (Data(), URL.response(requestURL, statusCode: 304))
      }
      return (
        data,
        URL.response(
          requestURL,
          headerFields: ["ETag": eTag, "Last-Modified": Self.lastModified]
        )
      )
    }
  }

  // Backdates only lastUpdate, so stored validators survive into the refresh.
  private func refreshStale(_ podcastID: Podcast.ID) async throws {
    _ = try await appDB.unsafeTestDB.write { db in
      try Podcast.withID(podcastID).updateAll(db, Podcast.Columns.lastUpdate.set(to: 2.hoursAgo))
    }
    try await refreshManager.performRefresh(stalenessThreshold: .minutes(30))
  }

  private func podcast(_ podcastID: Podcast.ID) async throws -> Podcast {
    try #require(try await repo.podcastSeries(podcastID)).podcast
  }

  private func lastIfNoneMatch() async -> String? {
    await session.sentRequests.last?.value(forHTTPHeaderField: "If-None-Match")
  }
}
