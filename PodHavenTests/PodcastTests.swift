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

  @Test("podcastSeriesDetail(feedURL:iTunesID:) resolves by feedURL then iTunesID")
  func podcastSeriesDetailByFeedURLAndITunesIDResolution() async throws {
    let feedURL = FeedURL(URL(string: "https://example.com/identity-lookup.rss")!)
    let iTunesID = ITunesPodcastID(rawValue: 42)
    let series = try await repo.insertSeries(
      UnsavedPodcastSeries(
        unsavedPodcast: try Create.unsavedPodcast(feedURL: feedURL, iTunesID: iTunesID)
      )
    )

    // feedURL match wins; iTunesID supplied or not is irrelevant.
    let byFeed = try await repo.podcastSeriesDetail(feedURL, iTunesID: nil)
    #expect(byFeed?.id == series.id)
    #expect(byFeed?.podcast.iTunesID == iTunesID)

    // Wrong feedURL with matching iTunesID falls through to the iTunesID branch.
    let mismatchedFeed = FeedURL(URL(string: "https://example.com/different.rss")!)
    let byITunes = try await repo.podcastSeriesDetail(mismatchedFeed, iTunesID: iTunesID)
    #expect(byITunes?.id == series.id)

    // Neither matches.
    let unrelatedITunes = ITunesPodcastID(rawValue: 999)
    let nothing = try await repo.podcastSeriesDetail(mismatchedFeed, iTunesID: unrelatedITunes)
    #expect(nothing == nil)

    // No iTunesID stored; lookup with iTunesID falls back to nil correctly.
    let plainURL = FeedURL(URL(string: "https://example.com/plain.rss")!)
    let plainSeries = try await repo.insertSeries(
      UnsavedPodcastSeries(unsavedPodcast: try Create.unsavedPodcast(feedURL: plainURL))
    )
    let plainSeriesDetail = try await repo.podcastSeriesDetail(plainURL, iTunesID: nil)
    #expect(plainSeriesDetail?.id == plainSeries.id)
    #expect(plainSeriesDetail?.podcast.iTunesID == nil)
  }

  @Test("that a podcast feedURL must be valid")
  func failToInsertInvalidFeedURL() async throws {
    // Bad scheme
    let schemeURL = URL(string: "file://example.com/data")!
    await #expect(throws: (any Error).self) {
      try await self.repo.insertSeries(
        UnsavedPodcastSeries(
          unsavedPodcast: Create.unsavedPodcast(
            feedURL: FeedURL(schemeURL),
            title: "Scheme title"
          )
        )
      )
    }

    // Not absolute
    let relativeURL = URL(string: "https:/path/to/data")!
    await #expect(throws: (any Error).self) {
      try await self.repo.insertSeries(
        UnsavedPodcastSeries(
          unsavedPodcast: Create.unsavedPodcast(
            feedURL: FeedURL(relativeURL),
            title: "Relative title"
          )
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

  @Test("updateLastUpdates() writes per-row timestamps in a single transaction")
  func testUpdateLastUpdates() async throws {
    let podcastSeries1 = try await repo.insertSeries(
      UnsavedPodcastSeries(unsavedPodcast: try Create.unsavedPodcast(lastUpdate: 30.minutesAgo))
    )
    let podcastSeries2 = try await repo.insertSeries(
      UnsavedPodcastSeries(unsavedPodcast: try Create.unsavedPodcast(lastUpdate: 30.minutesAgo))
    )

    let time1 = Date().addingTimeInterval(-10)
    let time2 = Date()
    try await repo.updateLastUpdates([
      (podcastSeries1.podcast.id, time1),
      (podcastSeries2.podcast.id, time2),
    ])

    let fetched1 = try await repo.podcastSeries(podcastSeries1.podcast.id)!
    let fetched2 = try await repo.podcastSeries(podcastSeries2.podcast.id)!
    #expect(fetched1.podcast.lastUpdate.approximatelyEquals(time1))
    #expect(fetched2.podcast.lastUpdate.approximatelyEquals(time2))
  }

  @Test(
    "updatePodcastSettings() atomically updates every settings field and persists across fetches"
  )
  func testUpdatePodcastSettings() async throws {
    let podcastSeries = try await repo.insertSeries(
      UnsavedPodcastSeries(unsavedPodcast: try Create.unsavedPodcast())
    )
    #expect(podcastSeries.podcast.unsaved.settings == .defaults)

    let everythingSet = PodcastSettings(
      defaultPlaybackRate: 1.5,
      queueAllEpisodes: .onTop,
      cacheAllEpisodes: .save,
      notifyNewEpisodes: true,
      freshnessCadence: .evergreen
    )
    let updated = try await repo.updatePodcastSettings(podcastSeries.id, everythingSet)
    #expect(updated == true)
    let afterAllSet = try await repo.podcastSeries(podcastSeries.id)!
    #expect(afterAllSet.podcast.unsaved.settings == everythingSet)

    let everythingCleared = PodcastSettings.defaults
    let updated2 = try await repo.updatePodcastSettings(podcastSeries.id, everythingCleared)
    #expect(updated2 == true)
    let afterCleared = try await repo.podcastSeries(podcastSeries.id)!
    #expect(afterCleared.podcast.unsaved.settings == everythingCleared)

    let nonExistentID = Podcast.ID(99999)
    let updatedMissing = try await repo.updatePodcastSettings(nonExistentID, everythingSet)
    #expect(updatedMissing == false)
  }

  @Test("toOriginalUnsavedPodcast resets all user-generated fields")
  func toOriginalUnsavedPodcastResetsUserFields() throws {
    let unsavedPodcast = try Create.unsavedPodcast(
      lastUpdate: Date(),
      subscriptionDate: Date(),
      defaultPlaybackRate: 1.5,
      queueAllEpisodes: .onTop,
      cacheAllEpisodes: .save,
      freshnessCadence: .evergreen
    )

    let original = try unsavedPodcast.toOriginalUnsavedPodcast()

    #expect(original.lastUpdate == .epoch)
    #expect(original.subscriptionDate == nil)
    #expect(original.cacheAllEpisodes == .never)
    #expect(original.defaultPlaybackRate == nil)
    #expect(original.queueAllEpisodes == .never)
    #expect(original.freshnessCadence == nil)

    // Feed fields should be preserved
    #expect(original.feedURL == unsavedPodcast.feedURL)
    #expect(original.title == unsavedPodcast.title)
    #expect(original.image == unsavedPodcast.image)
    #expect(original.description == unsavedPodcast.description)
    #expect(original.link == unsavedPodcast.link)
  }

  @Test("freshnessCadence defaults to nil and round-trips every case through insert + fetch")
  func freshnessCadencePersistence() async throws {
    let defaultPodcast = try Create.unsavedPodcast()
    #expect(defaultPodcast.freshnessCadence == nil)
    let defaultSeries = try await repo.insertSeries(
      UnsavedPodcastSeries(unsavedPodcast: defaultPodcast)
    )
    #expect(defaultSeries.podcast.freshnessCadence == nil)
    let fetchedDefault = try await repo.podcastSeries(defaultSeries.id)
    #expect(fetchedDefault?.podcast.freshnessCadence == nil)

    for cadence in FreshnessCadence.allCases {
      let custom = try Create.unsavedPodcast(freshnessCadence: cadence)
      let series = try await repo.insertSeries(UnsavedPodcastSeries(unsavedPodcast: custom))
      #expect(series.podcast.freshnessCadence == cadence)
      let fetched = try await repo.podcastSeries(series.id)
      #expect(fetched?.podcast.freshnessCadence == cadence)
    }
  }

  @Test("updatePodcastSettings flips the freshness cadence across every case, including nil")
  func testUpdatePodcastSettingsCadenceSweep() async throws {
    let podcastSeries = try await repo.insertSeries(
      UnsavedPodcastSeries(unsavedPodcast: try Create.unsavedPodcast())
    )
    #expect(podcastSeries.podcast.freshnessCadence == nil)

    var settings = PodcastSettings.defaults
    let sequence: [FreshnessCadence?] = [.daily, .monthly, .evergreen, .weekly, nil]
    for cadence in sequence {
      settings.freshnessCadence = cadence
      let updated = try await repo.updatePodcastSettings(podcastSeries.id, settings)
      #expect(updated == true)
      let fetched = try await repo.podcastSeries(podcastSeries.id)!
      #expect(fetched.podcast.freshnessCadence == cadence)
    }
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

  @Test("untagged filter returns only podcasts with no tags")
  func testUntaggedFilter() async throws {
    let series1 = try await repo.insertSeries(
      UnsavedPodcastSeries(unsavedPodcast: Create.unsavedPodcast())
    )
    let series2 = try await repo.insertSeries(
      UnsavedPodcastSeries(unsavedPodcast: Create.unsavedPodcast())
    )
    let series3 = try await repo.insertSeries(
      UnsavedPodcastSeries(unsavedPodcast: Create.unsavedPodcast())
    )

    let tag = try await repo.insertTag(UnsavedTag(name: "Tech"))
    try await repo.addTag(tag.id, to: series1.id)

    let untagged = try await repo.db.read { db in
      try Podcast.all().having(Podcast.podcastTags.isEmpty).fetchAll(db)
    }
    #expect(untagged.count == 2)
    #expect(Set(untagged.map(\.id)) == Set([series2.id, series3.id]))

    // Tagging the remaining podcasts should make untagged empty
    try await repo.addTag(tag.id, to: series2.id)
    try await repo.addTag(tag.id, to: series3.id)

    let untaggedAfter = try await repo.db.read { db in
      try Podcast.all().having(Podcast.podcastTags.isEmpty).fetchAll(db)
    }
    #expect(untaggedAfter.isEmpty)
  }

}
