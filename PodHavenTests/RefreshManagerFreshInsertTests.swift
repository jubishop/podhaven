// Copyright Justin Bishop, 2026

import FactoryKit
import FactoryTesting
import Foundation
import Testing

@testable import PodHaven

@Suite("of RefreshManager fresh insert tests", .container)
actor RefreshManagerFreshInsertTests {
  @DynamicInjected(\.podcastFeedSession) private var podcastFeedSession
  @DynamicInjected(\.refreshManager) private var refreshManager
  @DynamicInjected(\.repo) private var repo

  private var session: FakeDataFetchable {
    podcastFeedSession as! FakeDataFetchable
  }

  @Test("performRefresh skips a series inserted from a feed fetched moments earlier")
  func freshlyFetchedSeriesIsNotRefetched() async throws {
    await SyntheticFeed.respond(session, episodes: 1)
    let neverFetched = try await repo.insertSeries(
      UnsavedPodcastSeries(
        unsavedPodcast: try Create.unsavedPodcast(feedURL: FeedURL(SyntheticFeed.url(0)))
      )
    )

    let fetched = try await Create.unsavedPodcast(feedURL: FeedURL(SyntheticFeed.url(1)))
      .getOrCreatePodcast()
    let insertRequests = await session.requests
    #expect(insertRequests == [fetched.feedURL.rawValue])

    try await refreshManager.performRefresh(stalenessThreshold: .hours(1))

    let refreshRequests = Array(await session.requests.dropFirst(insertRequests.count))
    #expect(refreshRequests == [neverFetched.podcast.feedURL.rawValue])
  }
}
