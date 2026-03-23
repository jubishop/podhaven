// Copyright Justin Bishop, 2025

import FactoryKit
import FactoryTesting
import Foundation
import GRDB
import Testing

@testable import PodHaven

@Suite("of iTunes ID tests", .container)
class ITunesIDTests {
  @DynamicInjected(\.repo) private var repo
  @DynamicInjected(\.observatory) private var observatory

  // MARK: - Repo: podcastSeries(feedURL:, iTunesID:)

  @Test("podcastSeries finds by feedURL when iTunesID is nil")
  func testPodcastSeriesByFeedURLOnly() async throws {
    let feedURL = FeedURL(URL(string: "https://example.com/feed.rss")!)
    let unsavedPodcast = try Create.unsavedPodcast(feedURL: feedURL, title: "Test Podcast")
    try await repo.insertSeries(UnsavedPodcastSeries(unsavedPodcast: unsavedPodcast))

    let result = try await repo.podcastSeries(feedURL)
    #expect(result != nil)
    #expect(result?.podcast.title == "Test Podcast")
  }

  @Test("podcastSeries finds by iTunesID when feedURL doesn't match")
  func testPodcastSeriesByITunesID() async throws {
    let dbFeedURL = FeedURL(URL(string: "https://example.com/canonical-feed.rss")!)
    let iTunesID = ITunesPodcastID(12345)
    let unsavedPodcast = try Create.unsavedPodcast(
      feedURL: dbFeedURL,
      iTunesID: iTunesID,
      title: "Podcast With ID"
    )
    try await repo.insertSeries(UnsavedPodcastSeries(unsavedPodcast: unsavedPodcast))

    // Search with a different feedURL but matching iTunesID
    let searchFeedURL = FeedURL(URL(string: "https://example.com/itunes-feed.rss")!)
    let result = try await repo.podcastSeries(searchFeedURL, iTunesID: iTunesID)
    #expect(result != nil)
    #expect(result?.podcast.title == "Podcast With ID")
    #expect(result?.podcast.feedURL == dbFeedURL)
  }

  @Test("podcastSeries returns nil when neither feedURL nor iTunesID match")
  func testPodcastSeriesNoMatch() async throws {
    let unsavedPodcast = try Create.unsavedPodcast(
      feedURL: FeedURL(URL(string: "https://example.com/feed.rss")!),
      iTunesID: ITunesPodcastID(111)
    )
    try await repo.insertSeries(UnsavedPodcastSeries(unsavedPodcast: unsavedPodcast))

    let result = try await repo.podcastSeries(
      FeedURL(URL(string: "https://other.com/feed.rss")!),
      iTunesID: ITunesPodcastID(999)
    )
    #expect(result == nil)
  }

  @Test("podcastSeries prefers feedURL match when both could match different podcasts")
  func testPodcastSeriesFeedURLPreference() async throws {
    let feedURL = FeedURL(URL(string: "https://example.com/feed-a.rss")!)
    let podcast1 = try Create.unsavedPodcast(
      feedURL: feedURL,
      iTunesID: ITunesPodcastID(111),
      title: "Podcast A"
    )
    try await repo.insertSeries(UnsavedPodcastSeries(unsavedPodcast: podcast1))

    // Insert second podcast that matches by iTunesID 999
    let podcast2 = try Create.unsavedPodcast(
      feedURL: FeedURL(URL(string: "https://example.com/feed-b.rss")!),
      iTunesID: ITunesPodcastID(999),
      title: "Podcast B"
    )
    try await repo.insertSeries(UnsavedPodcastSeries(unsavedPodcast: podcast2))

    // Query with feedURL matching Podcast A and iTunesID matching Podcast B
    // Should return Podcast A (feedURL takes priority)
    let result = try await repo.podcastSeries(feedURL, iTunesID: ITunesPodcastID(999))
    #expect(result != nil)
    #expect(result?.podcast.title == "Podcast A")
  }

  // MARK: - Repo: updateITunesID

  @Test("updateITunesID backfills iTunesID on existing podcast")
  func testUpdateITunesID() async throws {
    let unsavedPodcast = try Create.unsavedPodcast(title: "No ID Yet")
    let series = try await repo.insertSeries(
      UnsavedPodcastSeries(unsavedPodcast: unsavedPodcast)
    )
    #expect(series.podcast.iTunesID == nil)

    let iTunesID = ITunesPodcastID(42)
    let updated = try await repo.updateITunesID(series.podcast.id, iTunesID: iTunesID)
    #expect(updated)

    let fetched = try await repo.podcastSeries(series.podcast.id)
    #expect(fetched?.podcast.iTunesID == iTunesID)
  }

  @Test("updateITunesID returns false for non-existent podcast")
  func testUpdateITunesIDNonExistent() async throws {
    let result = try await repo.updateITunesID(Podcast.ID(99999), iTunesID: ITunesPodcastID(1))
    #expect(result == false)
  }

  // MARK: - Repo: upsertPodcastEpisodes iTunesID dedup

  @Test("upsertPodcastEpisodes finds existing podcast by iTunesID when feedURLs diverge")
  func testUpsertFindsExistingByITunesID() async throws {
    let dbFeedURL = FeedURL(URL(string: "https://example.com/canonical.rss")!)
    let iTunesID = ITunesPodcastID(555)
    let unsavedPodcast = try Create.unsavedPodcast(
      feedURL: dbFeedURL,
      iTunesID: iTunesID,
      title: "Canonical Podcast"
    )
    let series = try await repo.insertSeries(
      UnsavedPodcastSeries(unsavedPodcast: unsavedPodcast)
    )

    // Upsert with different feedURL but same iTunesID
    let iTunesFeedURL = FeedURL(URL(string: "https://example.com/itunes.rss")!)
    let upsertPodcast = try Create.unsavedPodcast(
      feedURL: iTunesFeedURL,
      iTunesID: iTunesID,
      title: "iTunes Title"
    )
    let upsertEpisode = try Create.unsavedEpisode()

    let results = try await repo.upsertPodcastEpisodes([
      UnsavedPodcastEpisode(unsavedPodcast: upsertPodcast, unsavedEpisode: upsertEpisode)
    ])

    // Should reuse the existing podcast (same ID), not create a new one
    #expect(results.count == 1)
    #expect(results[0].podcast.id == series.podcast.id)
    #expect(results[0].podcast.feedURL == dbFeedURL)

    // Verify no duplicate podcast was created
    let allPodcasts = try await repo.allPodcasts(AppDB.NoOp)
    #expect(allPodcasts.count == 1)
  }

  @Test("upsertPodcastEpisodes uses iTunesID cache for multiple episodes")
  func testUpsertITunesIDCache() async throws {
    let dbFeedURL = FeedURL(URL(string: "https://example.com/canonical.rss")!)
    let iTunesID = ITunesPodcastID(777)
    let unsavedPodcast = try Create.unsavedPodcast(
      feedURL: dbFeedURL,
      iTunesID: iTunesID,
      title: "Cached Podcast"
    )
    try await repo.insertSeries(UnsavedPodcastSeries(unsavedPodcast: unsavedPodcast))

    // Upsert multiple episodes with different feedURL but same iTunesID
    let iTunesFeedURL = FeedURL(URL(string: "https://example.com/itunes.rss")!)
    let upsertPodcast = try Create.unsavedPodcast(
      feedURL: iTunesFeedURL,
      iTunesID: iTunesID,
      title: "iTunes Title"
    )
    let episode1 = try Create.unsavedEpisode()
    let episode2 = try Create.unsavedEpisode()

    let results = try await repo.upsertPodcastEpisodes([
      UnsavedPodcastEpisode(unsavedPodcast: upsertPodcast, unsavedEpisode: episode1),
      UnsavedPodcastEpisode(unsavedPodcast: upsertPodcast, unsavedEpisode: episode2),
    ])

    // Both episodes should be associated with the same podcast
    #expect(results.count == 2)
    #expect(results[0].podcast.id == results[1].podcast.id)

    let allPodcasts = try await repo.allPodcasts(AppDB.NoOp)
    #expect(allPodcasts.count == 1)
  }

  // MARK: - Observatory: podcastsWithEpisodeMetadata with iTunesIDs

  @Test("podcastsWithEpisodeMetadata finds podcasts by iTunesID")
  func testObservatoryITunesIDMatch() async throws {
    let feedURL = FeedURL(URL(string: "https://example.com/canonical.rss")!)
    let iTunesID = ITunesPodcastID(888)
    let unsavedPodcast = try Create.unsavedPodcast(
      feedURL: feedURL,
      iTunesID: iTunesID,
      title: "Observable Podcast"
    )
    try await repo.insertSeries(
      UnsavedPodcastSeries(
        unsavedPodcast: unsavedPodcast,
        unsavedEpisodes: [Create.unsavedEpisode()]
      )
    )

    // Query with different feedURL but matching iTunesID
    let searchFeedURL = FeedURL(URL(string: "https://example.com/itunes.rss")!)
    let results: [PodcastWithEpisodeMetadata<Podcast>] =
      try await observatory.podcastsWithEpisodeMetadata(
        [searchFeedURL],
        iTunesIDs: [iTunesID]
      )
      .get()

    #expect(results.count == 1)
    #expect(results[0].podcast.title == "Observable Podcast")
    #expect(results[0].episodeCount == 1)
  }

  @Test("podcastsWithEpisodeMetadata with empty iTunesIDs behaves like feedURL-only query")
  func testObservatoryEmptyITunesIDs() async throws {
    let feedURL = FeedURL(URL(string: "https://example.com/feed.rss")!)
    let unsavedPodcast = try Create.unsavedPodcast(feedURL: feedURL, title: "Feed Only")
    try await repo.insertSeries(
      UnsavedPodcastSeries(
        unsavedPodcast: unsavedPodcast,
        unsavedEpisodes: [Create.unsavedEpisode()]
      )
    )

    let results: [PodcastWithEpisodeMetadata<Podcast>] =
      try await observatory.podcastsWithEpisodeMetadata([feedURL]).get()
    #expect(results.count == 1)
    #expect(results[0].podcast.title == "Feed Only")

    // Non-matching feedURL with no iTunesIDs
    let otherURL = FeedURL(URL(string: "https://other.com/feed.rss")!)
    let noResults: [PodcastWithEpisodeMetadata<Podcast>] =
      try await observatory.podcastsWithEpisodeMetadata([otherURL]).get()
    #expect(noResults.isEmpty)
  }

  // MARK: - PodcastFeed: toUnsavedPodcast with iTunesID

  @Test("toUnsavedPodcast passes through iTunesID")
  func testPodcastFeedITunesID() async throws {
    let data = PreviewBundle.loadAsset(named: "pod_save_america", in: .FeedRSS)
    let fakeURL = FeedURL(URL(string: "https://example.com/feed.rss")!)
    let feed = try await PodcastFeed.parse(data, from: fakeURL)

    let iTunesID = ITunesPodcastID(1234)
    let unsavedPodcast = try feed.toUnsavedPodcast(iTunesID: iTunesID)
    #expect(unsavedPodcast.iTunesID == iTunesID)
  }

  @Test("toUnsavedPodcast defaults iTunesID to nil")
  func testPodcastFeedNoITunesID() async throws {
    let data = PreviewBundle.loadAsset(named: "pod_save_america", in: .FeedRSS)
    let fakeURL = FeedURL(URL(string: "https://example.com/feed.rss")!)
    let feed = try await PodcastFeed.parse(data, from: fakeURL)

    let unsavedPodcast = try feed.toUnsavedPodcast()
    #expect(unsavedPodcast.iTunesID == nil)
  }

  @Test("toUnsavedPodcast preserves existing iTunesID when merging")
  func testPodcastFeedMergePreservesITunesID() async throws {
    let data = PreviewBundle.loadAsset(named: "pod_save_america", in: .FeedRSS)
    let fakeURL = FeedURL(URL(string: "https://example.com/feed.rss")!)
    let feed = try await PodcastFeed.parse(data, from: fakeURL)

    // Insert a podcast with iTunesID
    let existingITunesID = ITunesPodcastID(9999)
    let existingPodcast = try Create.unsavedPodcast(
      feedURL: fakeURL,
      iTunesID: existingITunesID
    )
    let series = try await repo.insertSeries(
      UnsavedPodcastSeries(unsavedPodcast: existingPodcast)
    )

    // Merge without explicit iTunesID — should preserve existing
    let merged = try feed.toUnsavedPodcast(merging: series.podcast)
    #expect(merged.iTunesID == existingITunesID)
  }

  @Test("toUnsavedPodcast explicit iTunesID overrides merged value")
  func testPodcastFeedExplicitITunesIDOverridesMerge() async throws {
    let data = PreviewBundle.loadAsset(named: "pod_save_america", in: .FeedRSS)
    let fakeURL = FeedURL(URL(string: "https://example.com/feed.rss")!)
    let feed = try await PodcastFeed.parse(data, from: fakeURL)

    let existingPodcast = try Create.unsavedPodcast(
      feedURL: fakeURL,
      iTunesID: ITunesPodcastID(111)
    )
    let series = try await repo.insertSeries(
      UnsavedPodcastSeries(unsavedPodcast: existingPodcast)
    )

    // Explicit iTunesID should take priority
    let newITunesID = ITunesPodcastID(222)
    let merged = try feed.toUnsavedPodcast(merging: series.podcast, iTunesID: newITunesID)
    #expect(merged.iTunesID == newITunesID)
  }

  @Test("toUnsavedSeries passes iTunesID through to podcast")
  func testPodcastFeedSeriesiTunesID() async throws {
    let data = PreviewBundle.loadAsset(named: "pod_save_america", in: .FeedRSS)
    let fakeURL = FeedURL(URL(string: "https://example.com/feed.rss")!)
    let feed = try await PodcastFeed.parse(data, from: fakeURL)

    let iTunesID = ITunesPodcastID(5678)
    let unsavedSeries = try feed.toUnsavedSeries(iTunesID: iTunesID)
    #expect(unsavedSeries.unsavedPodcast.iTunesID == iTunesID)
  }

  // MARK: - UnsavedPodcast.getOrCreatePodcast with iTunesID lookup

  @Test("getOrCreatePodcast resolves UnsavedPodcast to saved Podcast via iTunesID")
  func testGetOrCreatePodcastITunesIDResolution() async throws {
    let dbFeedURL = FeedURL(URL(string: "https://example.com/canonical.rss")!)
    let iTunesID = ITunesPodcastID(444)
    let unsavedPodcast = try Create.unsavedPodcast(
      feedURL: dbFeedURL,
      iTunesID: iTunesID,
      title: "Saved Podcast"
    )
    let series = try await repo.insertSeries(
      UnsavedPodcastSeries(unsavedPodcast: unsavedPodcast)
    )

    // Create a bridged UnsavedPodcast with different feedURL but same iTunesID
    let searchFeedURL = FeedURL(URL(string: "https://example.com/itunes.rss")!)
    let bridged = try Create.unsavedPodcast(
      feedURL: searchFeedURL,
      iTunesID: iTunesID,
      title: "Saved Podcast"
    )

    // Should resolve to the existing saved podcast, not create a new one
    let resolved = try await bridged.getOrCreatePodcast()
    #expect(resolved.id == series.podcast.id)
    #expect(resolved.feedURL == dbFeedURL)

    let allPodcasts = try await repo.allPodcasts(AppDB.NoOp)
    #expect(allPodcasts.count == 1)
  }

  // MARK: - toOriginalUnsavedPodcast preserves iTunesID

  @Test("toOriginalUnsavedPodcast preserves iTunesID")
  func testOriginalUnsavedPodcastPreservesITunesID() throws {
    let iTunesID = ITunesPodcastID(42)
    let unsavedPodcast = try Create.unsavedPodcast(
      iTunesID: iTunesID,
      lastUpdate: Date(),
      subscriptionDate: Date()
    )

    let original = try unsavedPodcast.toOriginalUnsavedPodcast()
    #expect(original.iTunesID == iTunesID)
    // User fields should be reset
    #expect(original.subscriptionDate == nil)
    #expect(original.lastUpdate == .epoch)
  }
}
