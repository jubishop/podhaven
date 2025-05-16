// Copyright Justin Bishop, 2025

import FactoryKit
import FactoryTesting
import Foundation
import GRDB
import Testing

@testable import PodHaven

@Suite("of Podcast model tests", .container)
class PodcastTests {
  @DynamicInjected(\.repo) private var repo

  @Test("that a podcast can be created, fetched, and deleted")
  func createSinglePodcast() async throws {
    let url = URL(string: "https://example.com/data")!
    let unsavedPodcast = try TestHelpers.unsavedPodcast(feedURL: FeedURL(url))
    let unsavedEpisode = try TestHelpers.unsavedEpisode()
    let podcastSeries = try await repo.insertSeries(
      unsavedPodcast,
      unsavedEpisodes: [unsavedEpisode]
    )
    let podcast = podcastSeries.podcast
    #expect(podcast.title == unsavedPodcast.title)

    let fetchedPodcast = try await repo.db.read { [podcast] db in
      try Podcast.withID(podcast.id).fetchOne(db)
    }
    #expect(fetchedPodcast == podcast)

    let urlFilteredPodcastSeries = try await repo.podcastSeries(podcast.feedURL)
    #expect(urlFilteredPodcastSeries?.podcast == podcast)

    let fetchedAllPodcasts = try await repo.db.read { db in
      try Podcast.fetchAll(db)
    }
    #expect(fetchedAllPodcasts == [podcast])

    try await repo.db.read { [podcast] db in
      let exists = try podcast.exists(db)
      #expect(exists)
    }
    let deleted = try await repo.delete(podcast.id)
    #expect(deleted)
    try await repo.db.read { [podcast] db in
      let exists = try podcast.exists(db)
      #expect(!exists)
    }

    let noPodcasts = try await repo.db.read { db in
      try Podcast.fetchAll(db)
    }
    #expect(noPodcasts.isEmpty)

    let allCount = try await repo.db.read { db in
      try Podcast.fetchCount(db)
    }
    #expect(allCount == 0)

    let titleCount = try await repo.db.read { [podcast] db in
      try Podcast.filter { $0.title == podcast.title }.fetchCount(db)
    }
    #expect(titleCount == 0)
  }

  @Test("that a podcast feedURL must be valid")
  func failToInsertInvalidFeedURL() async throws {
    // Bad scheme
    let schemeTitle = "Scheme title"
    let schemeURL = URL(string: "file://example.com/data")!
    await #expect(
      throws: ModelError.podcastInitializationFailure(
        feedURL: FeedURL(schemeURL),
        title: schemeTitle,
        caught: URLError(.badURL, userInfo: ["message": "URL: \(schemeURL) must use https scheme."])
      )
    ) {
      try await self.repo.insertSeries(
        TestHelpers.unsavedPodcast(
          feedURL: FeedURL(schemeURL),
          title: schemeTitle
        )
      )
    }

    // Not absolute
    let relativeTitle = "Relative title"
    let relativeURL = URL(string: "https:/path/to/data")!
    await #expect(
      throws: ModelError.podcastInitializationFailure(
        feedURL: FeedURL(relativeURL),
        title: relativeTitle,
        caught: URLError(
          .badURL,
          userInfo: ["message": "URL: \(relativeURL) must have a valid host."]
        )
      )
    ) {
      try await self.repo.insertSeries(
        TestHelpers.unsavedPodcast(feedURL: FeedURL(relativeURL), title: relativeTitle)
      )
    }
  }

  @Test("that a podcast feedURL converts http to https as needed")
  func convertFeedURLToHTTPS() async throws {
    let url = URL(string: "http://example.com/data#fragment")!
    let unsavedPodcast = try TestHelpers.unsavedPodcast(feedURL: FeedURL(url))
    let podcastSeries = try await repo.insertSeries(unsavedPodcast)
    let podcast = podcastSeries.podcast
    #expect(podcast.feedURL == FeedURL(URL(string: "https://example.com/data#fragment")!))
  }

  @Test("that a podcast feedURL adds https as needed")
  func convertFeedURLAddsHTTPS() async throws {
    let url = URL(string: "example.com/data#fragment")!
    let unsavedPodcast = try TestHelpers.unsavedPodcast(feedURL: FeedURL(url))
    let podcastSeries = try await repo.insertSeries(unsavedPodcast)
    let podcast = podcastSeries.podcast
    #expect(podcast.feedURL == FeedURL(URL(string: "https://example.com/data#fragment")!))
  }

  @Test("that trying to set the same podcast feedURL throws error")
  func updateExistingPodcastOnConflict() async throws {
    let url = URL(string: "https://example.com/data")!
    let unsavedPodcast = try TestHelpers.unsavedPodcast(feedURL: FeedURL(url), title: "Old Title")
    _ = try await repo.insertSeries(unsavedPodcast)
    let unsavedPodcast2 = try TestHelpers.unsavedPodcast(feedURL: FeedURL(url), title: "New Title")
    await #expect(throws: (any Error).self) {
      _ = try await self.repo.insertSeries(unsavedPodcast2)
    }
  }

  @Test("allPodcasts()")
  func testAll() async throws {
    let freshPodcast = try TestHelpers.unsavedPodcast(lastUpdate: Date())
    let stalePodcast = try TestHelpers.unsavedPodcast(lastUpdate: 10.minutesAgo)
    let unsubscribedPodcast = try TestHelpers.unsavedPodcast(subscribed: false)
    try await repo.insertSeries(freshPodcast)
    try await repo.insertSeries(stalePodcast)
    try await repo.insertSeries(unsubscribedPodcast)

    let allPodcasts = try await repo.allPodcasts()
    #expect(allPodcasts.count == 3)
  }

  @Test("allPodcastSeries()")
  func testAllPodcastSeries() async throws {
    let freshPodcast = try TestHelpers.unsavedPodcast(lastUpdate: Date())
    let stalePodcast = try TestHelpers.unsavedPodcast(lastUpdate: 10.minutesAgo)
    let unsubscribedPodcast = try TestHelpers.unsavedPodcast(subscribed: false)
    try await repo.insertSeries(freshPodcast)
    try await repo.insertSeries(stalePodcast)
    try await repo.insertSeries(unsubscribedPodcast)

    let allPodcastSeries = try await repo.allPodcastSeries()
    #expect(allPodcastSeries.count == 3)
  }

  @Test("markSubscribed() successfully marks multiple podcasts as subscribed")
  func testMarkSubscribed() async throws {
    let podcastSeries1 = try await repo.insertSeries(
      try TestHelpers.unsavedPodcast(subscribed: false)
    )
    #expect(podcastSeries1.podcast.subscribed == false)
    let podcastSeries2 = try await repo.insertSeries(
      try TestHelpers.unsavedPodcast(subscribed: false)
    )
    #expect(podcastSeries2.podcast.subscribed == false)
    let podcastSeries3 = try await repo.insertSeries(
      try TestHelpers.unsavedPodcast(subscribed: true)
    )
    #expect(podcastSeries3.podcast.subscribed == true)

    try await repo.markSubscribed([podcastSeries1.id, podcastSeries2.id, podcastSeries3.id])

    let fetchedPodcast1 = try await repo.podcastSeries(podcastSeries1.id)!
    #expect(fetchedPodcast1.podcast.subscribed == true)
    let fetchedPodcast2 = try await repo.podcastSeries(podcastSeries2.id)!
    #expect(fetchedPodcast2.podcast.subscribed == true)
    let fetchedPodcast3 = try await repo.podcastSeries(podcastSeries3.id)!
    #expect(fetchedPodcast3.podcast.subscribed == true)
  }

  @Test("markUnsubscribed() successfully marks multiple podcasts as unsubscribed")
  func testMarkUnsubscribed() async throws {
    let podcastSeries1 = try await repo.insertSeries(
      try TestHelpers.unsavedPodcast(subscribed: true)
    )
    #expect(podcastSeries1.podcast.subscribed == true)
    let podcastSeries2 = try await repo.insertSeries(
      try TestHelpers.unsavedPodcast(subscribed: true)
    )
    #expect(podcastSeries2.podcast.subscribed == true)
    let podcastSeries3 = try await repo.insertSeries(
      try TestHelpers.unsavedPodcast(subscribed: false)
    )
    #expect(podcastSeries3.podcast.subscribed == false)

    try await repo.markUnsubscribed([podcastSeries1.id, podcastSeries2.id, podcastSeries3.id])

    let fetchedPodcast1 = try await repo.podcastSeries(podcastSeries1.id)!
    #expect(fetchedPodcast1.podcast.subscribed == false)
    let fetchedPodcast2 = try await repo.podcastSeries(podcastSeries2.id)!
    #expect(fetchedPodcast2.podcast.subscribed == false)
    let fetchedPodcast3 = try await repo.podcastSeries(podcastSeries3.id)!
    #expect(fetchedPodcast3.podcast.subscribed == false)
  }
}
