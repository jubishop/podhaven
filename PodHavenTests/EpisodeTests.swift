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
      subscribed: false
    )
    let unsavedEpisode = try Create.unsavedEpisode(
      media: MediaURL(URL.valid()),
      title: "original episode title",
      pubDate: 100.minutesAgo,
      duration: CMTime.inSeconds(300),
      description: "original episode description",
      link: URL.valid(),
      image: URL.valid(),
      currentTime: CMTime.inSeconds(60)
    )
    let podcastSeries = try await repo.insertSeries(
      unsavedPodcast,
      unsavedEpisodes: [unsavedEpisode]
    )

    let originalPodcast = podcastSeries.podcast
    let originalEpisode = podcastSeries.episodes.first!

    // Step 2: Update user state and duration (simulating PodAVPlayer updating duration)
    let actualDuration = CMTime.inSeconds(1800)  // 30 minutes actual duration from media file
    try await repo.markSubscribed(originalPodcast.id)
    try await repo.markComplete(originalEpisode.id)
    try await repo.updateCurrentTime(originalEpisode.id, CMTime.inSeconds(120))
    try await repo.updateDuration(originalEpisode.id, actualDuration)
    try await queue.unshift(originalEpisode.id)

    // Step 3: Call updateSeries with RSS feed data (simulating what would come from a feed refresh)
    let newFeedURL = FeedURL(URL.valid())
    let newPodcastTitle = "new podcast title"
    let newPodcastImage = URL.valid()
    let newPodcastDescription = "new podcast description"
    let newPodcastLink = URL.valid()
    let newLastUpdate = Date()

    var updatedPodcast = originalPodcast
    updatedPodcast.feedURL = newFeedURL
    updatedPodcast.title = newPodcastTitle
    updatedPodcast.image = newPodcastImage
    updatedPodcast.description = newPodcastDescription
    updatedPodcast.link = newPodcastLink
    updatedPodcast.lastUpdate = newLastUpdate

    let newEpisodeMedia = MediaURL(URL.valid())
    let newEpisodeTitle = "new episode title"
    let newEpisodePubDate = 50.minutesAgo
    let newEpisodeDuration = CMTime.inSeconds(600)
    let newEpisodeDescription = "new episode description"
    let newEpisodeLink = URL.valid()
    let newEpisodeImage = URL.valid()

    var updatedEpisode = originalEpisode
    updatedEpisode.media = newEpisodeMedia
    updatedEpisode.title = newEpisodeTitle
    updatedEpisode.pubDate = newEpisodePubDate
    updatedEpisode.duration = newEpisodeDuration
    updatedEpisode.description = newEpisodeDescription
    updatedEpisode.link = newEpisodeLink
    updatedEpisode.image = newEpisodeImage

    let newEpisode = try Create.unsavedEpisode(title: "episode 2")
    try await repo.updateSeries(
      updatedPodcast,
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
      "media", "title", "pubDate", "description", "link", "image",
    ])
    #expect(
      episodeRSSColumnNames == expectedEpisodeColumns,
      "Test must be updated if Episode.rssUpdatableColumns changes"
    )

    // RSS attributes should be updated for existing episode (excluding duration and guid)
    #expect(updatedExistingEpisode.media == newEpisodeMedia)
    #expect(updatedExistingEpisode.title == newEpisodeTitle)
    #expect(updatedExistingEpisode.pubDate.approximatelyEquals(newEpisodePubDate))
    #expect(updatedExistingEpisode.description == newEpisodeDescription)
    #expect(updatedExistingEpisode.link == newEpisodeLink)
    #expect(updatedExistingEpisode.image == newEpisodeImage)

    // Non-RSS attributes should be preserved (not overwritten by original values)
    #expect(updatedSeries.podcast.subscribed == true)
    #expect(updatedExistingEpisode.currentTime == CMTime.inSeconds(120))
    #expect(updatedExistingEpisode.completionDate != nil)
    #expect(updatedExistingEpisode.queueOrder == 0)
    #expect(updatedExistingEpisode.duration == actualDuration)
  }

  @Test("that episode GUID cannot be updated once set")
  func preventGuidUpdate() async throws {
    let unsavedPodcast = try Create.unsavedPodcast()
    let unsavedEpisode = try Create.unsavedEpisode(guid: GUID("original-guid"))
    let podcastSeries = try await repo.insertSeries(
      unsavedPodcast,
      unsavedEpisodes: [unsavedEpisode]
    )

    let episode = podcastSeries.episodes.first!

    // Attempt to update GUID directly in database should fail
    await #expect(throws: DatabaseError.self) {
      try await self.appDB.db.write { db in
        try Episode
          .withID(episode.id)
          .updateAll(db, Episode.Columns.guid.set(to: GUID("different-guid")))
      }
    }
  }

  @Test("that episodes can persist currentTime")
  func persistCurrentTime() async throws {
    let guid = GUID("guid")
    let cmTime = CMTime.inSeconds(30)

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

    let newCMTime = CMTime.inSeconds(60)
    try await repo.updateCurrentTime(episode.id, newCMTime)

    let updatedEpisode = try await repo.db.read { db in
      try Episode.fetchOne(db, id: episode.id)
    }!
    #expect(updatedEpisode.currentTime == newCMTime)
  }

  @Test("that episodes can persist duration")
  func persistDuration() async throws {
    let guid = GUID("guid")
    let cmTime = CMTime.inSeconds(30)

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

    let newCMTime = CMTime.inSeconds(60)
    try await repo.updateDuration(episode.id, newCMTime)

    let updatedEpisode = try await repo.db.read { db in
      try Episode.fetchOne(db, id: episode.id)
    }!
    #expect(updatedEpisode.duration == newCMTime)
  }

  @Test("that an episode can be marked complete")
  func markEpisodeComplete() async throws {
    let unsavedPodcast = try Create.unsavedPodcast()
    let unsavedEpisode = try Create.unsavedEpisode(currentTime: CMTime.inSeconds(60))
    let podcastSeries = try await repo.insertSeries(
      unsavedPodcast,
      unsavedEpisodes: [unsavedEpisode]
    )

    let episode = podcastSeries.episodes.first!
    #expect(episode.completed == false)
    #expect(episode.currentTime == CMTime.inSeconds(60))
    try await repo.markComplete(episode.id)

    let podcastEpisode = try await repo.episode(episode.id)!
    #expect(podcastEpisode.episode.completed == true)
    #expect(podcastEpisode.episode.currentTime == CMTime.zero)
  }

  @Test("that upsertPodcastEpisode works when podcast exists or is new")
  func testAddEpisode() async throws {
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

    let fetchedPodcastEpisode = try await repo.episode(insertedPodcastEpisode.id)!
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

  @Test("that upsertPodcastEpisodes works when fetching existing")
  func testAddEpisodesFetchExisting() async throws {
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
      fetchedPodcastEpisodes.append(try await repo.episode(podcastEpisode.id)!)
    }
    #expect(Set(podcastEpisodes) == Set(fetchedPodcastEpisodes))
  }
}
