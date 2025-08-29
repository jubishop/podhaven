// Copyright Justin Bishop, 2025

import AVFoundation
import FactoryKit
import FactoryTesting
import Foundation
import GRDB
import Testing

@testable import PodHaven

@Suite("of Episode model tests", .container)
class EpisodeTests {
  @DynamicInjected(\.appDB) private var appDB
  @DynamicInjected(\.queue) private var queue
  @DynamicInjected(\.repo) private var repo

  @Test("that episodes are created and fetched in the right order")
  func createSeveralEpisodes() async throws {
    let url = URL.valid()
    let unsavedPodcast = try Create.unsavedPodcast(feedURL: FeedURL(url))

    let newestUnsavedEpisode = try Create.unsavedEpisode()
    let oldUnsavedEpisode = try Create.unsavedEpisode(pubDate: 10.minutesAgo)
    let middleUnsavedEpisode = try Create.unsavedEpisode(pubDate: 5.minutesAgo)
    let ancientUnsavedEpisode = try Create.unsavedEpisode(pubDate: 1000.minutesAgo)

    try await repo.insertSeries(
      unsavedPodcast,
      unsavedEpisodes: [
        middleUnsavedEpisode,
        ancientUnsavedEpisode,
        oldUnsavedEpisode,
        newestUnsavedEpisode,
      ]
    )

    let podcastSeries = try await repo.db.read { db in
      try Podcast
        .filter { $0.feedURL == url }
        .including(all: Podcast.episodes)
        .asRequest(of: PodcastSeries.self)
        .fetchOne(db)
    }!
    #expect(
      podcastSeries.episodes.elements
        == podcastSeries.episodes.sorted { $0.pubDate > $1.pubDate }
    )
  }

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
      media: MediaURL(URL.valid()),
      title: "original episode title",
      pubDate: 100.minutesAgo,
      duration: CMTime.seconds(300),
      description: "original episode description",
      link: URL.valid(),
      image: URL.valid()
    )
    let podcastSeries = try await repo.insertSeries(
      unsavedPodcast,
      unsavedEpisodes: [unsavedEpisode]
    )

    let originalPodcast = podcastSeries.podcast
    let originalEpisode = podcastSeries.episodes.first!

    // Step 2: Update user state and duration (simulating PodAVPlayer updating duration)
    let actualDuration = CMTime.seconds(1800)  // 30 minutes actual duration from media file
    let currentTime = CMTime.seconds(120)
    try await repo.markSubscribed(originalPodcast.id)
    try await repo.markComplete(originalEpisode.id)
    try await repo.updateCurrentTime(originalEpisode.id, currentTime)
    try await repo.updateDuration(originalEpisode.id, actualDuration)
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
        media: newEpisodeMedia,
        title: newEpisodeTitle,
        pubDate: newEpisodePubDate,
        duration: newEpisodeDuration,
        description: newEpisodeDescription,
        link: newEpisodeLink,
        image: newEpisodeImage
      )
    )

    let newEpisode = try Create.unsavedEpisode(title: "episode 2")
    try await repo.updateSeriesFromFeed(
      podcastID: updatedPodcast.id,
      podcast: updatedPodcast,
      unsavedEpisodes: [newEpisode],
      existingEpisodes: [updatedEpisode]
    )

    // Step 4: Confirm user state from step 2 wasn't overwritten by step 3
    let updatedSeries = try await repo.podcastSeries(originalPodcast.id)!
    let updatedExistingEpisode = updatedSeries.episodes.first { $0.title == newEpisodeTitle }!

    // Verify we're testing all Podcast RSS columns (test will fail if rssUpdatableColumns changes)
    let podcastRSSColumnNames = Set(updatedPodcast.rssUpdatableColumns.map { $0.0.name })
    let expectedPodcastColumns = Set([
      "feedURL", "title", "image", "description", "link", "lastUpdate",
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
    #expect(updatedSeries.podcast.lastUpdate.approximatelyEquals(newLastUpdate))

    // Verify we're testing all Episode RSS columns (test will fail if rssUpdatableColumns changes)
    let episodeRSSColumnNames = Set(updatedEpisode.rssUpdatableColumns.map { $0.0.name })
    let expectedEpisodeColumns = Set([
      "guid", "media", "title", "pubDate", "description", "link", "image",
    ])
    #expect(
      episodeRSSColumnNames == expectedEpisodeColumns,
      "Test must be updated if Episode.rssUpdatableColumns changes"
    )

    // RSS attributes should be updated for existing episode (excluding duration)
    #expect(updatedExistingEpisode.guid == newEpisodeGUID)
    #expect(updatedExistingEpisode.media == newEpisodeMedia)
    #expect(updatedExistingEpisode.title == newEpisodeTitle)
    #expect(updatedExistingEpisode.pubDate.approximatelyEquals(newEpisodePubDate))
    #expect(updatedExistingEpisode.description == newEpisodeDescription)
    #expect(updatedExistingEpisode.link == newEpisodeLink)
    #expect(updatedExistingEpisode.image == newEpisodeImage)

    // Non-RSS attributes should be preserved (not overwritten by original values)
    #expect(updatedSeries.podcast.subscribed == true)
    #expect(updatedExistingEpisode.currentTime == currentTime)
    #expect(updatedExistingEpisode.completionDate != nil)
    #expect(updatedExistingEpisode.queueOrder == 0)
    #expect(updatedExistingEpisode.duration == actualDuration)
  }

  @Test("that episode GUID can be updated")
  func guidUpdateAllowed() async throws {
    let unsavedPodcast = try Create.unsavedPodcast()
    let unsavedEpisode = try Create.unsavedEpisode(guid: GUID("original-guid"))
    let podcastSeries = try await repo.insertSeries(
      unsavedPodcast,
      unsavedEpisodes: [unsavedEpisode]
    )

    let episode = podcastSeries.episodes.first!

    let updatedGUID: GUID = GUID(String.random())
    _ = try await self.appDB.db.write { db in
      try Episode
        .withID(episode.id)
        .updateAll(db, Episode.Columns.guid.set(to: updatedGUID))
    }

    let updatedEpisode: Episode? = try await repo.episode(episode.id)
    #expect(updatedEpisode?.guid == updatedGUID)
  }

  @Test("that episodes can persist currentTime")
  func persistCurrentTime() async throws {
    let guid = GUID("guid")
    let cmTime = CMTime.seconds(30)

    let unsavedPodcast = try Create.unsavedPodcast()
    let unsavedEpisode = try Create.unsavedEpisode(guid: guid, currentTime: cmTime)
    let podcastSeries = try await repo.insertSeries(
      unsavedPodcast,
      unsavedEpisodes: [unsavedEpisode]
    )
    let podcast = podcastSeries.podcast

    let episode = try await repo.db.read { db in
      try Episode.fetchOne(db, key: ["guid": guid, "podcastId": podcast.id])
    }!
    #expect(episode.currentTime == cmTime)

    let newCMTime = CMTime.seconds(60)
    try await repo.updateCurrentTime(episode.id, newCMTime)

    let updatedEpisode = try await repo.db.read { db in
      try Episode.fetchOne(db, id: episode.id)
    }!
    #expect(updatedEpisode.currentTime == newCMTime)
  }

  @Test("that episodes can persist duration")
  func persistDuration() async throws {
    let guid = GUID("guid")
    let cmTime = CMTime.seconds(30)

    let unsavedPodcast = try Create.unsavedPodcast()
    let unsavedEpisode = try Create.unsavedEpisode(guid: guid, duration: cmTime)
    let podcastSeries = try await repo.insertSeries(
      unsavedPodcast,
      unsavedEpisodes: [unsavedEpisode]
    )
    let podcast = podcastSeries.podcast

    let episode = try await repo.db.read { db in
      try Episode.fetchOne(db, key: ["guid": guid, "podcastId": podcast.id])
    }!
    #expect(episode.duration == cmTime)

    let newCMTime = CMTime.seconds(60)
    try await repo.updateDuration(episode.id, newCMTime)

    let updatedEpisode = try await repo.db.read { db in
      try Episode.fetchOne(db, id: episode.id)
    }!
    #expect(updatedEpisode.duration == newCMTime)
  }

  @Test("that episodes can persist cachedFilename")
  func persistCachedFilename() async throws {
    let guid = GUID("guid")
    let initialCachedFilename = "initial-cache.mp3"

    let unsavedPodcast = try Create.unsavedPodcast()
    let unsavedEpisode = try Create.unsavedEpisode(
      guid: guid,
      cachedFilename: initialCachedFilename
    )
    let podcastSeries = try await repo.insertSeries(
      unsavedPodcast,
      unsavedEpisodes: [unsavedEpisode]
    )
    let podcast = podcastSeries.podcast

    let episode = try await repo.db.read { db in
      try Episode.fetchOne(db, key: ["guid": guid, "podcastId": podcast.id])
    }!
    #expect(episode.cachedFilename == initialCachedFilename)

    let newCachedFilename = "new-cache.mp3"
    try await repo.updateCachedFilename(episode.id, newCachedFilename)

    let updatedEpisode = try await repo.db.read { db in
      try Episode.fetchOne(db, id: episode.id)
    }!
    #expect(updatedEpisode.cachedFilename == newCachedFilename)

    // Test clearing the cached filename (setting to nil)
    try await repo.updateCachedFilename(episode.id, nil)

    let clearedEpisode = try await repo.db.read { db in
      try Episode.fetchOne(db, id: episode.id)
    }!
    #expect(clearedEpisode.cachedFilename == nil)
  }

  @Test("that an episode can be marked complete")
  func markEpisodeComplete() async throws {
    let unsavedPodcast = try Create.unsavedPodcast()
    let unsavedEpisode = try Create.unsavedEpisode(currentTime: CMTime.seconds(60))
    let podcastSeries = try await repo.insertSeries(
      unsavedPodcast,
      unsavedEpisodes: [unsavedEpisode]
    )

    let episode = podcastSeries.episodes.first!
    #expect(episode.completed == false)
    #expect(episode.currentTime == CMTime.seconds(60))
    try await repo.markComplete(episode.id)

    let completedEpisode: Episode? = try await repo.episode(episode.id)!
    #expect(completedEpisode?.completed == true)
    #expect(completedEpisode?.currentTime == CMTime.zero)
  }

  @Test("that upsertPodcastEpisode works")
  func testUpsertPodcastEpisode() async throws {
    let unsavedPodcast = try Create.unsavedPodcast()
    let unsavedEpisode = try Create.unsavedEpisode()
    let insertedPodcastEpisode = try await repo.upsertPodcastEpisode(
      UnsavedPodcastEpisode(
        unsavedPodcast: unsavedPodcast,
        unsavedEpisode: unsavedEpisode
      )
    )
    #expect(insertedPodcastEpisode.podcast.feedURL == unsavedPodcast.feedURL)
    #expect(insertedPodcastEpisode.episode.media == unsavedEpisode.media)

    let fetchedPodcastEpisode = try await repo.podcastEpisode(insertedPodcastEpisode.id)!
    #expect(fetchedPodcastEpisode.podcast.title == insertedPodcastEpisode.podcast.title)
    #expect(fetchedPodcastEpisode.episode.guid == insertedPodcastEpisode.episode.guid)

    let secondUnsavedEpisode = try Create.unsavedEpisode()
    let _ = try await repo.upsertPodcastEpisode(
      UnsavedPodcastEpisode(
        unsavedPodcast: unsavedPodcast,
        unsavedEpisode: secondUnsavedEpisode
      )
    )

    let fetchedPodcastSeries = try await repo.podcastSeries(unsavedPodcast.feedURL)!
    #expect(fetchedPodcastSeries.episodes.count == 2)
  }

  @Test("that upsertPodcastEpisode updates new podcast and episode with matching unique keys")
  func testUpsertExistingPodcastAndEpisodeWithMatchingUniqueKeys() async throws {
    let unsavedPodcast = try Create.unsavedPodcast()
    let unsavedEpisode = try Create.unsavedEpisode()
    let originalPodcastEpisode = try await repo.upsertPodcastEpisode(
      UnsavedPodcastEpisode(
        unsavedPodcast: unsavedPodcast,
        unsavedEpisode: unsavedEpisode
      )
    )

    let matchingPodcast = try Create.unsavedPodcast(
      feedURL: unsavedPodcast.feedURL,
      title: "New Podcast Title"
    )
    let matchingEpisode = try Create.unsavedEpisode(
      media: unsavedEpisode.media,
      title: "New Episode Titlu"
    )

    let updatedPodcastEpisode = try await repo.upsertPodcastEpisode(
      UnsavedPodcastEpisode(
        unsavedPodcast: matchingPodcast,
        unsavedEpisode: matchingEpisode
      )
    )
    #expect(originalPodcastEpisode.id == updatedPodcastEpisode.id)

    #expect(updatedPodcastEpisode.podcast.title == matchingPodcast.title)
    #expect(updatedPodcastEpisode.episode.title == matchingEpisode.title)

    let fetchedPodcastEpisode = try await repo.podcastEpisode(updatedPodcastEpisode.id)!
    #expect(fetchedPodcastEpisode.podcast.title == updatedPodcastEpisode.podcast.title)
    #expect(fetchedPodcastEpisode.episode.title == updatedPodcastEpisode.episode.title)
  }

  @Test("that upsertPodcastEpisodes mix of Existing and New")
  func testUpsertEpisodesMixOfExistingAndNew() async throws {
    let insertedPodcast = try Create.unsavedPodcast()
    let insertedEpisode = try Create.unsavedEpisode()
    let unsavedEpisodeInsertedPodcast = try Create.unsavedEpisode()
    try await repo.insertSeries(insertedPodcast, unsavedEpisodes: [insertedEpisode])

    let unsavedPodcast = try Create.unsavedPodcast()
    let unsavedEpisode = try Create.unsavedEpisode()

    let allPodcasts = [insertedPodcast, unsavedPodcast]
    let allEpisodes = [insertedEpisode, unsavedEpisodeInsertedPodcast, unsavedEpisode]

    let podcastEpisodes = try await repo.upsertPodcastEpisodes(
      [
        UnsavedPodcastEpisode(
          unsavedPodcast: insertedPodcast,
          unsavedEpisode: insertedEpisode
        ),
        UnsavedPodcastEpisode(
          unsavedPodcast: insertedPodcast,
          unsavedEpisode: unsavedEpisodeInsertedPodcast
        ),
        UnsavedPodcastEpisode(
          unsavedPodcast: unsavedPodcast,
          unsavedEpisode: unsavedEpisode
        ),
      ]
    )
    #expect(podcastEpisodes.count == 3)
    #expect(Set(podcastEpisodes.map(\.podcast.feedURL)) == Set(allPodcasts.map(\.feedURL)))
    #expect(Set(podcastEpisodes.map(\.episode.media)) == Set(allEpisodes.map(\.media)))

    var fetchedPodcastEpisodes: [PodcastEpisode] = []
    for podcastEpisode in podcastEpisodes {
      fetchedPodcastEpisodes.append(try await repo.podcastEpisode(podcastEpisode.id)!)
    }
    #expect(Set(podcastEpisodes) == Set(fetchedPodcastEpisodes))
  }

  @Test("that latestEpisode returns the most recent episode for a podcast")
  func latestEpisode() async throws {
    let unsavedPodcast = try Create.unsavedPodcast()

    let oldestEpisode = try Create.unsavedEpisode(pubDate: 100.minutesAgo)
    let middleEpisode = try Create.unsavedEpisode(pubDate: 50.minutesAgo)
    let newestEpisode = try Create.unsavedEpisode(pubDate: 10.minutesAgo)

    let podcastSeries = try await repo.insertSeries(
      unsavedPodcast,
      unsavedEpisodes: [oldestEpisode, newestEpisode, middleEpisode]
    )

    let latestEpisode = try await repo.latestEpisode(for: podcastSeries.podcast.id)

    #expect(latestEpisode != nil)
    #expect(latestEpisode?.guid == newestEpisode.guid)
    #expect(latestEpisode?.pubDate.approximatelyEquals(newestEpisode.pubDate) == true)
  }

  @Test("that latestEpisode returns nil when podcast has no episodes")
  func latestEpisodeNoPodcast() async throws {
    let unsavedPodcast = try Create.unsavedPodcast()
    let podcastSeries = try await repo.insertSeries(unsavedPodcast, unsavedEpisodes: [])
    let latestEpisode = try await repo.latestEpisode(for: podcastSeries.id)

    #expect(latestEpisode == nil)
  }

  @Test("that insertSeries adds creationDates")
  func testInsertSeriesCreationDate() async throws {
    let creationDate = Date()
    let unsavedPodcast = try Create.unsavedPodcast()
    let unsavedEpisodes = try [Create.unsavedEpisode(), Create.unsavedEpisode()]
    let series = try await repo.insertSeries(unsavedPodcast, unsavedEpisodes: unsavedEpisodes)

    #expect(
      series.podcast.creationDate.approximatelyEquals(creationDate),
      "Podcast should have creationDate"
    )
    for episode in series.episodes {
      #expect(
        episode.creationDate.approximatelyEquals(creationDate),
        "Episode '\(episode.title)' should have creationDate"
      )
    }
  }

  @Test("that upserts dont modify creationDates")
  func testUpsertsDontModifyCreationDates() async throws {
    let unsavedPodcast = try Create.unsavedPodcast()
    let unsavedEpisode = try Create.unsavedEpisode()
    let insertedPodcastEpisode = try await repo.upsertPodcastEpisode(
      UnsavedPodcastEpisode(
        unsavedPodcast: unsavedPodcast,
        unsavedEpisode: unsavedEpisode
      )
    )

    let creationDate = insertedPodcastEpisode.podcast.creationDate
    let matchingPodcast = try Create.unsavedPodcast(feedURL: unsavedPodcast.feedURL)
    let matchingEpisode = try Create.unsavedEpisode(media: unsavedEpisode.media)

    let updatedPodcastEpisode = try await repo.upsertPodcastEpisode(
      UnsavedPodcastEpisode(
        unsavedPodcast: matchingPodcast,
        unsavedEpisode: matchingEpisode
      )
    )
    #expect(updatedPodcastEpisode.podcast.creationDate.approximatelyEquals(creationDate))
    #expect(updatedPodcastEpisode.episode.creationDate.approximatelyEquals(creationDate))

    let fetchedPodcastEpisode = try await repo.podcastEpisode(updatedPodcastEpisode.id)!
    #expect(fetchedPodcastEpisode.podcast.creationDate.approximatelyEquals(creationDate))
    #expect(fetchedPodcastEpisode.episode.creationDate.approximatelyEquals(creationDate))
  }
}
