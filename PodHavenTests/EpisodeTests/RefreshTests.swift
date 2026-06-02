// Copyright Justin Bishop, 2025

import AVFoundation
import FactoryKit
import FactoryTesting
import Foundation
import GRDB
import Testing

@testable import PodHaven

@Suite("of Episode refresh tests", .container)
class EpisodeRefreshTests {
  @DynamicInjected(\.queue) private var queue
  @DynamicInjected(\.repo) private var repo
  @DynamicInjected(\.userSettings) private var userSettings

  @Test("that a series with new episodes can be refreshed")
  func refreshSeriesWithNewEpisodes() async throws {
    // Step 1: Insert podcast and episodes into repo
    let unsavedPodcast = try Create.unsavedPodcast(
      feedURL: FeedURL(URL.valid()),
      title: "original podcast title",
      image: URL.valid(),
      description: "original podcast description",
      link: URL.valid(),
      subscriptionDate: nil
    )
    let unsavedEpisode = try Create.unsavedEpisode(
      mediaURL: MediaURL(URL.valid()),
      title: "original episode title",
      pubDate: 100.minutesAgo,
      duration: CMTime.seconds(300),
      description: "original episode description",
      link: URL.valid(),
      image: URL.valid()
    )
    let podcastSeries = try await repo.insertSeries(
      UnsavedPodcastSeries(
        unsavedPodcast: unsavedPodcast,
        unsavedEpisodes: [unsavedEpisode]
      )
    )

    let originalPodcast = podcastSeries.podcast
    let originalEpisode = podcastSeries.episodes.first!

    // Step 2: Update user state and duration (simulating PodAVPlayer updating duration)
    let actualDuration = CMTime.seconds(1800)  // 30 minutes actual duration from media file
    let currentTime = CMTime.seconds(120)
    try await repo.markSubscribed(originalPodcast.id)
    try await repo.markFinished(originalEpisode.id)
    try await repo.updateCurrentTime(originalEpisode.id, currentTime: currentTime)
    try await repo.updateDuration(originalEpisode.id, duration: actualDuration)
    try await queue.unshift(originalEpisode.id)

    // Step 3: Call updateSeries with RSS feed data (simulating what would come from a feed refresh)
    let newFeedURL = FeedURL(URL.valid())
    let newPodcastTitle = "new podcast title"
    let newPodcastImage = URL.valid()
    let newPodcastDescription = "new podcast description"
    let newPodcastLink = URL.valid()
    let newLastUpdate = 10.minutesAgo

    let updatedPodcast = try Podcast(
      id: originalPodcast.id,
      creationDate: originalPodcast.creationDate,
      from: Create.unsavedPodcast(
        feedURL: newFeedURL,
        title: newPodcastTitle,
        image: newPodcastImage,
        description: newPodcastDescription,
        link: newPodcastLink,
        lastUpdate: newLastUpdate
      )
    )

    let newEpisodeGUID: GUID = GUID(String.random())
    let newEpisodeMedia = MediaURL(URL.valid())
    let newEpisodeTitle = "new episode title"
    let newEpisodePubDate = 50.minutesAgo
    let newEpisodeDuration = CMTime.seconds(600)
    let newEpisodeDescription = "new episode description"
    let newEpisodeLink = URL.valid()
    let newEpisodeImage = URL.valid()

    let updatedEpisode = try Episode(
      id: originalEpisode.id,
      creationDate: originalEpisode.creationDate,
      from: Create.unsavedEpisode(
        guid: newEpisodeGUID,
        mediaURL: newEpisodeMedia,
        title: newEpisodeTitle,
        pubDate: newEpisodePubDate,
        duration: newEpisodeDuration,
        description: newEpisodeDescription,
        link: newEpisodeLink,
        image: newEpisodeImage
      )
    )

    let newUnsavedEpisode = try Create.unsavedEpisode(title: "episode 2")
    let newEpisodes = try await repo.updateSeriesFromFeed(
      podcastSeries: PodcastSeries(podcast: updatedPodcast),
      podcast: updatedPodcast,
      unsavedEpisodes: [newUnsavedEpisode],
      existingEpisodes: [updatedEpisode]
    )
    #expect(newEpisodes.map(\.mediaGUID) == [newUnsavedEpisode.mediaGUID])

    // Step 4: Confirm user state from step 2 wasn't overwritten by step 3
    let updatedSeries = try await repo.podcastSeries(originalPodcast.id)!
    let updatedExistingEpisode = updatedSeries.episodes.first { $0.title == newEpisodeTitle }!

    // Verify we're testing all Podcast RSS columns (test will fail if rssUpdatableColumns changes)
    let podcastRSSColumnNames = Set(updatedPodcast.rssUpdatableColumns.map { $0.0.name })
    let expectedPodcastColumns = Set([
      "feedURL", "title", "image", "description", "link",
    ])
    #expect(
      podcastRSSColumnNames == expectedPodcastColumns,
      "Test must be updated if Podcast.rssUpdatableColumns changes"
    )

    // All RSS attributes should be updated for podcast
    #expect(updatedSeries.podcast.feedURL == newFeedURL)
    #expect(updatedSeries.podcast.title == newPodcastTitle)
    #expect(updatedSeries.podcast.image == newPodcastImage)
    #expect(updatedSeries.podcast.description == newPodcastDescription)
    #expect(updatedSeries.podcast.link == newPodcastLink)

    // Verify we're testing all Episode RSS columns (test will fail if rssUpdatableColumns changes)
    let episodeRSSColumnNames = Set(updatedEpisode.rssUpdatableColumns.map { $0.0.name })
    let expectedEpisodeColumns = Set([
      "guid", "mediaURL", "title", "pubDate", "description", "link", "image",
    ])
    #expect(
      episodeRSSColumnNames == expectedEpisodeColumns,
      "Test must be updated if Episode.rssUpdatableColumns changes"
    )

    // RSS attributes should be updated for existing episode (excluding duration)
    #expect(updatedExistingEpisode.guid == newEpisodeGUID)
    #expect(updatedExistingEpisode.mediaURL == newEpisodeMedia)
    #expect(updatedExistingEpisode.title == newEpisodeTitle)
    #expect(updatedExistingEpisode.pubDate.approximatelyEquals(newEpisodePubDate))
    #expect(updatedExistingEpisode.description == newEpisodeDescription)
    #expect(updatedExistingEpisode.link == newEpisodeLink)
    #expect(updatedExistingEpisode.image == newEpisodeImage)

    // Non-RSS attributes should be preserved (not overwritten by original values)
    #expect(updatedSeries.podcast.subscribed == true)
    #expect(updatedExistingEpisode.currentTime == currentTime)
    #expect(updatedExistingEpisode.finishDate != nil)
    #expect(updatedExistingEpisode.queueOrder == 0)
    #expect(updatedExistingEpisode.duration == actualDuration)
  }

  @Test("that two podcasts can persist the same guid and mediaURL")
  func crossPodcastDuplicateMediaGUID() async throws {
    let sharedGUID: GUID = GUID(String.random())
    let sharedMediaURL = MediaURL(URL.valid())

    let seriesA = try await repo.insertSeries(
      UnsavedPodcastSeries(
        unsavedPodcast: try Create.unsavedPodcast(title: "Podcast A"),
        unsavedEpisodes: [
          try Create.unsavedEpisode(
            guid: sharedGUID,
            mediaURL: sharedMediaURL,
            title: "Shared episode in A"
          )
        ]
      )
    )

    let seriesB = try await repo.insertSeries(
      UnsavedPodcastSeries(
        unsavedPodcast: try Create.unsavedPodcast(title: "Podcast B"),
        unsavedEpisodes: [try Create.unsavedEpisode(title: "B's own episode")]
      )
    )

    // Podcast B republishes an episode that already exists under Podcast A
    // with an identical guid and mediaURL, as overlapping Substack aggregate
    // and section feeds do. The per-podcast keys never collide here; only a
    // global (guid, mediaURL) key would, and it must not wipe B's whole feed.
    let duplicate = try Create.unsavedEpisode(
      guid: sharedGUID,
      mediaURL: sharedMediaURL,
      title: "Shared episode in B"
    )

    let inserted = try await repo.updateSeriesFromFeed(
      podcastSeries: PodcastSeries(podcast: seriesB.podcast),
      podcast: nil,
      unsavedEpisodes: [duplicate],
      existingEpisodes: []
    )
    #expect(inserted.map(\.mediaGUID) == [duplicate.mediaGUID])

    let refreshedB = try await repo.podcastSeries(seriesB.podcast.id)
    #expect(refreshedB?.episodes.contains { $0.mediaGUID == duplicate.mediaGUID } == true)

    let refreshedA = try await repo.podcastSeries(seriesA.podcast.id)
    #expect(
      refreshedA?.episodes
        .contains {
          $0.mediaGUID == MediaGUID(guid: sharedGUID, mediaURL: sharedMediaURL)
        } == true
    )
  }

  @Test("auto-queue limit trims the queue to a podcast's N newest episodes by pubDate")
  func autoQueueLimitKeepsNewestByPubDate() async throws {
    // Auto-queue on bottom, but keep only the two newest episodes queued.
    let podcast = try await Create.podcast(queueAllEpisodes: .onBottom, autoQueueLimit: 2)

    // Three episodes arrive in one refresh. Their feed order deliberately differs
    // from pubDate order so the test proves the OLDEST by pubDate is dropped, not
    // merely whichever landed last in the queue.
    let oldest = try Create.unsavedEpisode(title: "oldest", pubDate: 300.minutesAgo)
    let newest = try Create.unsavedEpisode(title: "newest", pubDate: 100.minutesAgo)
    let middle = try Create.unsavedEpisode(title: "middle", pubDate: 200.minutesAgo)

    let newEpisodes = try await repo.updateSeriesFromFeed(
      podcastSeries: PodcastSeries(podcast: podcast),
      podcast: nil,
      unsavedEpisodes: [oldest, newest, middle],
      existingEpisodes: []
    )
    #expect(newEpisodes.count == 3)

    let queuedTitles = try await repo.db.read { db in
      Set(try Episode.all().queued().fetchAll(db).map(\.title))
    }
    #expect(queuedTitles == ["newest", "middle"])
  }

  @Test("auto-queue limit is ignored when autoQueueLimit is unset")
  func autoQueueLimitUnsetKeepsEverything() async throws {
    let podcast = try await Create.podcast(queueAllEpisodes: .onBottom, autoQueueLimit: nil)

    let newEpisodes = try await repo.updateSeriesFromFeed(
      podcastSeries: PodcastSeries(podcast: podcast),
      podcast: nil,
      unsavedEpisodes: [
        try Create.unsavedEpisode(title: "a", pubDate: 300.minutesAgo),
        try Create.unsavedEpisode(title: "b", pubDate: 200.minutesAgo),
        try Create.unsavedEpisode(title: "c", pubDate: 100.minutesAgo),
      ],
      existingEpisodes: []
    )
    #expect(newEpisodes.count == 3)

    let queuedCount = try await repo.db.read { db in
      try Episode.all().queued().fetchCount(db)
    }
    #expect(queuedCount == 3)
  }

  @Test("auto-queue limit is not enforced on a refresh that queues no new episodes")
  func autoQueueLimitSkippedWhenNoNewEpisodes() async throws {
    // Auto-queue on bottom with a limit of 1, but the user has manually queued
    // two of the podcast's episodes — already above the limit.
    let podcastSeries = try await repo.insertSeries(
      UnsavedPodcastSeries(
        unsavedPodcast: try Create.unsavedPodcast(queueAllEpisodes: .onBottom, autoQueueLimit: 1),
        unsavedEpisodes: [
          try Create.unsavedEpisode(title: "older", pubDate: 200.minutesAgo),
          try Create.unsavedEpisode(title: "newer", pubDate: 100.minutesAgo),
        ]
      )
    )
    try await queue.append(podcastSeries.episodes.map(\.id))

    // A refresh arrives that queues nothing (e.g. only a metadata change).
    let newEpisodes = try await repo.updateSeriesFromFeed(
      podcastSeries: podcastSeries,
      podcast: nil,
      unsavedEpisodes: [],
      existingEpisodes: []
    )
    #expect(newEpisodes.isEmpty)

    // Both manually-queued episodes survive: the limit only trims when an
    // episode is actually auto-queued, not on every feed change.
    let queuedTitles = try await repo.db.read { db in
      Set(try Episode.all().queued().fetchAll(db).map(\.title))
    }
    #expect(queuedTitles == ["older", "newer"])
  }

  @Test(
    "auto-queue limit evicts the podcast's oldest to admit a newer episode when the queue is full"
  )
  func autoQueueLimitSwapsOldestWhenQueueFull() async throws {
    // Global queue holds only two episodes; the podcast keeps its two newest.
    userSettings.$maxQueueLength.new(2)

    let podcastSeries = try await repo.insertSeries(
      UnsavedPodcastSeries(
        unsavedPodcast: try Create.unsavedPodcast(queueAllEpisodes: .onBottom, autoQueueLimit: 2),
        unsavedEpisodes: [
          try Create.unsavedEpisode(title: "oldest", pubDate: 300.minutesAgo),
          try Create.unsavedEpisode(title: "middle", pubDate: 200.minutesAgo),
        ]
      )
    )
    // Fill the queue to its max with the podcast's two existing episodes.
    try await queue.append(podcastSeries.episodes.map(\.id))

    // A refresh brings a newer episode while the queue is already full.
    let newEpisodes = try await repo.updateSeriesFromFeed(
      podcastSeries: podcastSeries,
      podcast: nil,
      unsavedEpisodes: [try Create.unsavedEpisode(title: "newest", pubDate: 100.minutesAgo)],
      existingEpisodes: []
    )
    #expect(newEpisodes.count == 1)

    // The oldest is evicted to make room; the two newest remain queued.
    let queuedTitles = try await repo.db.read { db in
      Set(try Episode.all().queued().fetchAll(db).map(\.title))
    }
    #expect(queuedTitles == ["middle", "newest"])
  }

  @Test("auto-queue limit on top evicts the podcast's own oldest, not another podcast's, when full")
  func autoQueueLimitOnTopEvictsOwnOldestWhenQueueFull() async throws {
    userSettings.$maxQueueLength.new(3)

    // An unrelated podcast with one queued episode that must be left alone.
    let other = try await repo.insertSeries(
      UnsavedPodcastSeries(
        unsavedPodcast: try Create.unsavedPodcast(),
        unsavedEpisodes: [try Create.unsavedEpisode(title: "other", pubDate: 500.minutesAgo)]
      )
    )
    let podcastSeries = try await repo.insertSeries(
      UnsavedPodcastSeries(
        unsavedPodcast: try Create.unsavedPodcast(queueAllEpisodes: .onTop, autoQueueLimit: 2),
        unsavedEpisodes: [
          try Create.unsavedEpisode(title: "oldest", pubDate: 300.minutesAgo),
          try Create.unsavedEpisode(title: "middle", pubDate: 200.minutesAgo),
        ]
      )
    )
    // Fill the queue to its max of three: the other podcast plus this one's two.
    try await queue.append(other.episodes.map(\.id))
    try await queue.append(podcastSeries.episodes.map(\.id))

    // A refresh brings a newer episode for the limited podcast while full.
    _ = try await repo.updateSeriesFromFeed(
      podcastSeries: podcastSeries,
      podcast: nil,
      unsavedEpisodes: [try Create.unsavedEpisode(title: "newest", pubDate: 100.minutesAgo)],
      existingEpisodes: []
    )

    // The unrelated podcast keeps its episode; the limited podcast keeps its two
    // newest, with the freshly auto-queued episode placed on top of the queue.
    let queuedTitles = try await repo.db.read { db in
      try Episode.all().queued().order(\.queueOrder.asc).fetchAll(db).map(\.title)
    }
    #expect(queuedTitles == ["newest", "other", "middle"])
  }

  @Test("auto-queue limit does not evict when a refresh brings only episodes older than the limit")
  func autoQueueLimitDoesNotEvictWhenNoIncomingSurvives() async throws {
    // The podcast is already over its limit: three episodes queued, limit 2.
    let podcastSeries = try await repo.insertSeries(
      UnsavedPodcastSeries(
        unsavedPodcast: try Create.unsavedPodcast(queueAllEpisodes: .onBottom, autoQueueLimit: 2),
        unsavedEpisodes: [
          try Create.unsavedEpisode(title: "newest", pubDate: 100.minutesAgo),
          try Create.unsavedEpisode(title: "middle", pubDate: 200.minutesAgo),
          try Create.unsavedEpisode(title: "oldest", pubDate: 300.minutesAgo),
        ]
      )
    )
    try await queue.append(podcastSeries.episodes.map(\.id))

    // A refresh brings a brand-new episode older than everything queued, so it
    // never survives the limit window and is never auto-queued.
    let newEpisodes = try await repo.updateSeriesFromFeed(
      podcastSeries: podcastSeries,
      podcast: nil,
      unsavedEpisodes: [try Create.unsavedEpisode(title: "ancient", pubDate: 400.minutesAgo)],
      existingEpisodes: []
    )
    #expect(newEpisodes.count == 1)

    // Nothing was auto-queued, so nothing is evicted — all three remain queued.
    let queuedTitles = try await repo.db.read { db in
      Set(try Episode.all().queued().fetchAll(db).map(\.title))
    }
    #expect(queuedTitles == ["newest", "middle", "oldest"])
  }
}
