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
    let unsavedPodcast = try Create.unsavedPodcast(feedURL: FeedURL(url))
    let unsavedEpisode = try Create.unsavedEpisode()
    let podcastSeries = try await repo.insertSeries(
      UnsavedPodcastSeries(unsavedPodcast: unsavedPodcast, unsavedEpisodes: [unsavedEpisode])
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
    let deleted = try await repo.deletePodcast(podcast.id)
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
        UnsavedPodcastSeries(
          unsavedPodcast: Create.unsavedPodcast(
            feedURL: FeedURL(schemeURL),
            title: schemeTitle
          )
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
        UnsavedPodcastSeries(
          unsavedPodcast: Create.unsavedPodcast(feedURL: FeedURL(relativeURL), title: relativeTitle)
        )
      )
    }
  }

  @Test("that a podcast feedURL converts http to https as needed")
  func convertFeedURLToHTTPS() async throws {
    let url = URL(string: "http://example.com/data#fragment")!
    let unsavedPodcast = try Create.unsavedPodcast(feedURL: FeedURL(url))
    let podcastSeries = try await repo.insertSeries(
      UnsavedPodcastSeries(unsavedPodcast: unsavedPodcast)
    )
    let podcast = podcastSeries.podcast
    #expect(podcast.feedURL == FeedURL(URL(string: "https://example.com/data#fragment")!))
  }

  @Test("that a podcast feedURL adds https as needed")
  func convertFeedURLAddsHTTPS() async throws {
    let url = URL(string: "example.com/data#fragment")!
    let unsavedPodcast = try Create.unsavedPodcast(feedURL: FeedURL(url))
    let podcastSeries = try await repo.insertSeries(
      UnsavedPodcastSeries(unsavedPodcast: unsavedPodcast)
    )
    let podcast = podcastSeries.podcast
    #expect(podcast.feedURL == FeedURL(URL(string: "https://example.com/data#fragment")!))
  }

  @Test("that trying to set the same podcast feedURL throws error")
  func updateExistingPodcastOnConflict() async throws {
    let url = URL(string: "https://example.com/data")!
    let unsavedPodcast = try Create.unsavedPodcast(feedURL: FeedURL(url), title: "Old Title")
    _ = try await repo.insertSeries(UnsavedPodcastSeries(unsavedPodcast: unsavedPodcast))
    let unsavedPodcast2 = try Create.unsavedPodcast(feedURL: FeedURL(url), title: "New Title")
    await #expect(throws: (any Error).self) {
      _ = try await self.repo.insertSeries(UnsavedPodcastSeries(unsavedPodcast: unsavedPodcast2))
    }
  }

  @Test("allPodcasts()")
  func testAll() async throws {
    let freshPodcast = try Create.unsavedPodcast(lastUpdate: Date())
    let stalePodcast = try Create.unsavedPodcast(lastUpdate: 10.minutesAgo)
    let unsubscribedPodcast = try Create.unsavedPodcast(subscriptionDate: nil)
    try await repo.insertSeries(UnsavedPodcastSeries(unsavedPodcast: freshPodcast))
    try await repo.insertSeries(UnsavedPodcastSeries(unsavedPodcast: stalePodcast))
    try await repo.insertSeries(UnsavedPodcastSeries(unsavedPodcast: unsubscribedPodcast))

    let allPodcasts = try await repo.allPodcasts(AppDB.NoOp)
    #expect(allPodcasts.count == 3)
  }

  @Test("allPodcastSeries()")
  func testAllPodcastSeries() async throws {
    let freshPodcast = try Create.unsavedPodcast(
      lastUpdate: Date(),
      subscriptionDate: 10.minutesAgo
    )
    let stalePodcast = try Create.unsavedPodcast(
      lastUpdate: 10.minutesAgo,
      subscriptionDate: 20.minutesAgo
    )
    let unsubscribedPodcast = try Create.unsavedPodcast()
    let freshSeries = try await repo.insertSeries(
      UnsavedPodcastSeries(unsavedPodcast: freshPodcast)
    )
    let staleSeries = try await repo.insertSeries(
      UnsavedPodcastSeries(unsavedPodcast: stalePodcast)
    )
    let neverUpdatedSeries = try await repo.insertSeries(
      UnsavedPodcastSeries(unsavedPodcast: unsubscribedPodcast)
    )

    let allPodcastSeries = try await repo.allPodcastSeries(
      AppDB.NoOp,
      order: Podcast.Columns.lastUpdate.asc,
      limit: Int.max
    )
    #expect(allPodcastSeries.count == 3)
    #expect(allPodcastSeries == [neverUpdatedSeries, staleSeries, freshSeries])

    let limitedPodcastSeries = try await repo.allPodcastSeries(
      AppDB.NoOp,
      order: Podcast.Columns.id.asc,
      limit: 2
    )
    #expect(limitedPodcastSeries.count == 2)

    let subscribedPodcastSeries = try await repo.allPodcastSeries(
      Podcast.subscribed,
      order: Podcast.Columns.id.asc,
      limit: Int.max
    )
    #expect(Set(subscribedPodcastSeries) == Set([staleSeries, freshSeries]))
  }

  @Test("markSubscribed() successfully marks multiple podcasts as subscribed")
  func testMarkSubscribed() async throws {
    let podcastSeries1 = try await repo.insertSeries(
      UnsavedPodcastSeries(unsavedPodcast: try Create.unsavedPodcast(subscriptionDate: nil))
    )
    #expect(podcastSeries1.podcast.subscribed == false)
    let podcastSeries2 = try await repo.insertSeries(
      UnsavedPodcastSeries(unsavedPodcast: try Create.unsavedPodcast(subscriptionDate: nil))
    )
    #expect(podcastSeries2.podcast.subscribed == false)
    let podcastSeries3 = try await repo.insertSeries(
      UnsavedPodcastSeries(unsavedPodcast: try Create.unsavedPodcast(subscriptionDate: Date()))
    )
    #expect(podcastSeries3.podcast.subscribed == true)

    let subscriptionTime = Date()
    try await repo.markSubscribed([podcastSeries1.id, podcastSeries2.id, podcastSeries3.id])

    let fetchedPodcast1 = try await repo.podcastSeries(podcastSeries1.id)!
    #expect(fetchedPodcast1.podcast.subscribed == true)
    #expect(fetchedPodcast1.podcast.subscriptionDate!.approximatelyEquals(subscriptionTime))
    let fetchedPodcast2 = try await repo.podcastSeries(podcastSeries2.id)!
    #expect(fetchedPodcast2.podcast.subscribed == true)
    #expect(fetchedPodcast2.podcast.subscriptionDate!.approximatelyEquals(subscriptionTime))
    let fetchedPodcast3 = try await repo.podcastSeries(podcastSeries3.id)!
    #expect(fetchedPodcast3.podcast.subscribed == true)
    #expect(fetchedPodcast3.podcast.subscriptionDate!.approximatelyEquals(subscriptionTime))
  }

  @Test("markUnsubscribed() successfully marks multiple podcasts as unsubscribed")
  func testMarkUnsubscribed() async throws {
    let podcastSeries1 = try await repo.insertSeries(
      UnsavedPodcastSeries(unsavedPodcast: try Create.unsavedPodcast(subscriptionDate: Date()))
    )
    #expect(podcastSeries1.podcast.subscribed == true)
    let podcastSeries2 = try await repo.insertSeries(
      UnsavedPodcastSeries(unsavedPodcast: try Create.unsavedPodcast(subscriptionDate: Date()))
    )
    #expect(podcastSeries2.podcast.subscribed == true)
    let podcastSeries3 = try await repo.insertSeries(
      UnsavedPodcastSeries(unsavedPodcast: try Create.unsavedPodcast(subscriptionDate: nil))
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

  @Test("updateLastUpdate() successfully updates podcast lastUpdate timestamp")
  func testUpdateLastUpdate() async throws {
    let podcastSeries = try await repo.insertSeries(
      UnsavedPodcastSeries(unsavedPodcast: try Create.unsavedPodcast(lastUpdate: 30.minutesAgo))
    )

    let updateTime = Date()
    try await repo.updateLastUpdate(podcastSeries.podcast.id)

    let fetchedPodcast = try await repo.podcastSeries(podcastSeries.podcast.id)!
    #expect(fetchedPodcast.podcast.lastUpdate.approximatelyEquals(updateTime))
  }

  @Test("updateCacheAllEpisodes() successfully updates podcast cacheAllEpisodes setting")
  func testUpdateCacheAll() async throws {
    // Insert a podcast with default cacheAllEpisodes value (.never)
    let podcastSeries = try await repo.insertSeries(
      UnsavedPodcastSeries(unsavedPodcast: try Create.unsavedPodcast(cacheAllEpisodes: .never))
    )
    #expect(podcastSeries.podcast.cacheAllEpisodes == .never)

    // Update cacheAllEpisodes to .cache
    let updated = try await repo.updateCacheAllEpisodes(podcastSeries.id, cacheAllEpisodes: .cache)
    #expect(updated == true)

    // Verify the update worked
    let fetchedPodcast1 = try await repo.podcastSeries(podcastSeries.id)!
    #expect(fetchedPodcast1.podcast.cacheAllEpisodes == .cache)

    // Update cacheAllEpisodes to .save
    let updated2 = try await repo.updateCacheAllEpisodes(
      podcastSeries.id,
      cacheAllEpisodes: .save
    )
    #expect(updated2 == true)

    // Verify the update worked
    let fetchedPodcast2 = try await repo.podcastSeries(podcastSeries.id)!
    #expect(fetchedPodcast2.podcast.cacheAllEpisodes == .save)

    // Update cacheAllEpisodes back to .never
    let updated3 = try await repo.updateCacheAllEpisodes(podcastSeries.id, cacheAllEpisodes: .never)
    #expect(updated3 == true)

    // Verify the update worked
    let fetchedPodcast3 = try await repo.podcastSeries(podcastSeries.id)!
    #expect(fetchedPodcast3.podcast.cacheAllEpisodes == .never)

    // Try to update a non-existent podcast
    let nonExistentID = Podcast.ID(99999)
    let updated4 = try await repo.updateCacheAllEpisodes(nonExistentID, cacheAllEpisodes: .cache)
    #expect(updated4 == false)
  }

  @Test("updateDefaultPlaybackRate() successfully updates podcast defaultPlaybackRate setting")
  func testUpdateDefaultPlaybackRate() async throws {
    // Insert a podcast with default defaultPlaybackRate value (nil)
    let podcastSeries = try await repo.insertSeries(
      UnsavedPodcastSeries(unsavedPodcast: try Create.unsavedPodcast(defaultPlaybackRate: nil))
    )
    #expect(podcastSeries.podcast.defaultPlaybackRate == nil)

    // Update defaultPlaybackRate to 1.5
    let updated = try await repo.updateDefaultPlaybackRate(
      podcastSeries.id,
      defaultPlaybackRate: 1.5
    )
    #expect(updated == true)

    // Verify the update worked
    let fetchedPodcast1 = try await repo.podcastSeries(podcastSeries.id)!
    #expect(fetchedPodcast1.podcast.defaultPlaybackRate == 1.5)

    // Update defaultPlaybackRate to 1.25
    let updated2 = try await repo.updateDefaultPlaybackRate(
      podcastSeries.id,
      defaultPlaybackRate: 1.25
    )
    #expect(updated2 == true)

    // Verify the update worked
    let fetchedPodcast2 = try await repo.podcastSeries(podcastSeries.id)!
    #expect(fetchedPodcast2.podcast.defaultPlaybackRate == 1.25)

    // Update defaultPlaybackRate back to nil
    let updated3 = try await repo.updateDefaultPlaybackRate(
      podcastSeries.id,
      defaultPlaybackRate: nil
    )
    #expect(updated3 == true)

    // Verify the update worked
    let fetchedPodcast3 = try await repo.podcastSeries(podcastSeries.id)!
    #expect(fetchedPodcast3.podcast.defaultPlaybackRate == nil)

    // Try to update a non-existent podcast
    let nonExistentID = Podcast.ID(99999)
    let updated4 = try await repo.updateDefaultPlaybackRate(nonExistentID, defaultPlaybackRate: 1.0)
    #expect(updated4 == false)
  }

  @Test("toOriginalUnsavedPodcast resets all user-generated fields")
  func toOriginalUnsavedPodcastResetsUserFields() throws {
    let unsavedPodcast = try Create.unsavedPodcast(
      lastUpdate: Date(),
      subscriptionDate: Date(),
      defaultPlaybackRate: 1.5,
      queueAllEpisodes: .onTop,
      cacheAllEpisodes: .save
    )

    let original = try unsavedPodcast.toOriginalUnsavedPodcast()

    #expect(original.lastUpdate == .epoch)
    #expect(original.subscriptionDate == nil)
    #expect(original.cacheAllEpisodes == .never)
    #expect(original.defaultPlaybackRate == nil)
    #expect(original.queueAllEpisodes == .never)

    // Feed fields should be preserved
    #expect(original.feedURL == unsavedPodcast.feedURL)
    #expect(original.title == unsavedPodcast.title)
    #expect(original.image == unsavedPodcast.image)
    #expect(original.description == unsavedPodcast.description)
    #expect(original.link == unsavedPodcast.link)
  }

  @Test("queueAllEpisodes defaults to .never when not specified")
  func testQueueAllEpisodesDefaultValue() async throws {
    let unsavedPodcast = try Create.unsavedPodcast()
    let podcastSeries = try await repo.insertSeries(
      UnsavedPodcastSeries(unsavedPodcast: unsavedPodcast)
    )

    #expect(podcastSeries.podcast.unsaved.queueAllEpisodes == .never)
  }

  @Test("queueAllEpisodes is persisted and fetched correctly for all enum values")
  func testQueueAllEpisodesPersistence() async throws {
    // Test .onTop
    let onTopPodcast = try Create.unsavedPodcast(queueAllEpisodes: .onTop)
    let onTopSeries = try await repo.insertSeries(
      UnsavedPodcastSeries(unsavedPodcast: onTopPodcast)
    )
    #expect(onTopSeries.podcast.unsaved.queueAllEpisodes == .onTop)

    let fetchedOnTop = try await repo.podcastSeries(onTopSeries.id)
    #expect(fetchedOnTop?.podcast.unsaved.queueAllEpisodes == .onTop)

    // Test .onBottom
    let onBottomPodcast = try Create.unsavedPodcast(queueAllEpisodes: .onBottom)
    let onBottomSeries = try await repo.insertSeries(
      UnsavedPodcastSeries(unsavedPodcast: onBottomPodcast)
    )
    #expect(onBottomSeries.podcast.unsaved.queueAllEpisodes == .onBottom)

    let fetchedOnBottom = try await repo.podcastSeries(onBottomSeries.id)
    #expect(fetchedOnBottom?.podcast.unsaved.queueAllEpisodes == .onBottom)

    // Test .never
    let neverPodcast = try Create.unsavedPodcast(queueAllEpisodes: .never)
    let neverSeries = try await repo.insertSeries(
      UnsavedPodcastSeries(unsavedPodcast: neverPodcast)
    )
    #expect(neverSeries.podcast.unsaved.queueAllEpisodes == .never)

    let fetchedNever = try await repo.podcastSeries(neverSeries.id)
    #expect(fetchedNever?.podcast.unsaved.queueAllEpisodes == .never)
  }

  @Test("queueAllEpisodes value is preserved when reading from database")
  func testQueueAllEpisodesFromDatabase() async throws {
    let unsavedPodcast = try Create.unsavedPodcast(queueAllEpisodes: .onTop)
    let podcastSeries = try await repo.insertSeries(
      UnsavedPodcastSeries(unsavedPodcast: unsavedPodcast)
    )

    // Fetch directly from database using GRDB
    let fetchedFromDB = try await repo.podcastSeries(podcastSeries.id)

    #expect(fetchedFromDB?.podcast.queueAllEpisodes == .onTop)
  }

  @Test("updateQueueAllEpisodes() successfully updates podcast queueAllEpisodes setting")
  func testUpdateQueueAllEpisodes() async throws {
    // Insert a podcast with default queueAllEpisodes value (.never)
    let podcastSeries = try await repo.insertSeries(
      UnsavedPodcastSeries(unsavedPodcast: try Create.unsavedPodcast(queueAllEpisodes: .never))
    )
    #expect(podcastSeries.podcast.unsaved.queueAllEpisodes == .never)

    // Update queueAllEpisodes to .onTop
    let updated = try await repo.updateQueueAllEpisodes(podcastSeries.id, queueAllEpisodes: .onTop)
    #expect(updated == true)

    // Verify the update worked
    let fetchedPodcast1 = try await repo.podcastSeries(podcastSeries.id)!
    #expect(fetchedPodcast1.podcast.unsaved.queueAllEpisodes == .onTop)

    // Update queueAllEpisodes to .onBottom
    let updated2 = try await repo.updateQueueAllEpisodes(
      podcastSeries.id,
      queueAllEpisodes: .onBottom
    )
    #expect(updated2 == true)

    // Verify the update worked
    let fetchedPodcast2 = try await repo.podcastSeries(podcastSeries.id)!
    #expect(fetchedPodcast2.podcast.unsaved.queueAllEpisodes == .onBottom)

    // Update queueAllEpisodes back to .never
    let updated3 = try await repo.updateQueueAllEpisodes(podcastSeries.id, queueAllEpisodes: .never)
    #expect(updated3 == true)

    // Verify the update worked
    let fetchedPodcast3 = try await repo.podcastSeries(podcastSeries.id)!
    #expect(fetchedPodcast3.podcast.unsaved.queueAllEpisodes == .never)

    // Try to update a non-existent podcast
    let nonExistentID = Podcast.ID(99999)
    let updated4 = try await repo.updateQueueAllEpisodes(nonExistentID, queueAllEpisodes: .onTop)
    #expect(updated4 == false)
  }

  @Test("updateNotifyNewEpisodes() successfully updates podcast notifyNewEpisodes setting")
  func testUpdateNotifyNewEpisodes() async throws {
    // Insert a podcast with default notifyNewEpisodes value (false)
    let podcastSeries = try await repo.insertSeries(
      UnsavedPodcastSeries(unsavedPodcast: try Create.unsavedPodcast(notifyNewEpisodes: false))
    )
    #expect(podcastSeries.podcast.notifyNewEpisodes == false)

    // Update notifyNewEpisodes to true
    let updated = try await repo.updateNotifyNewEpisodes(podcastSeries.id, notifyNewEpisodes: true)
    #expect(updated == true)

    // Verify the update worked
    let fetchedPodcast1 = try await repo.podcastSeries(podcastSeries.id)!
    #expect(fetchedPodcast1.podcast.notifyNewEpisodes == true)

    // Update notifyNewEpisodes back to false
    let updated2 = try await repo.updateNotifyNewEpisodes(
      podcastSeries.id,
      notifyNewEpisodes: false
    )
    #expect(updated2 == true)

    // Verify the update worked
    let fetchedPodcast2 = try await repo.podcastSeries(podcastSeries.id)!
    #expect(fetchedPodcast2.podcast.notifyNewEpisodes == false)

    // Try to update a non-existent podcast
    let nonExistentID = Podcast.ID(99999)
    let updated3 = try await repo.updateNotifyNewEpisodes(nonExistentID, notifyNewEpisodes: true)
    #expect(updated3 == false)
  }
}
