// Copyright Justin Bishop, 2025

import AVFoundation
import FactoryKit
import FactoryTesting
import Foundation
import GRDB
import Testing

@testable import PodHaven

@Suite("Episode upsert tests", .container)
class EpisodeUpsertTests {
  @DynamicInjected(\.appDB) private var appDB
  @DynamicInjected(\.queue) private var queue
  @DynamicInjected(\.repo) private var repo

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
    #expect(insertedPodcastEpisode.episode.mediaURL == unsavedEpisode.mediaURL)

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
      mediaURL: unsavedEpisode.mediaURL,
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
    try await repo.insertSeries(
      UnsavedPodcastSeries(unsavedPodcast: insertedPodcast, unsavedEpisodes: [insertedEpisode])
    )

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
    #expect(Set(podcastEpisodes.map(\.episode.mediaURL)) == Set(allEpisodes.map(\.mediaURL)))

    var fetchedPodcastEpisodes: [PodcastEpisode] = []
    for podcastEpisode in podcastEpisodes {
      fetchedPodcastEpisodes.append(try await repo.podcastEpisode(podcastEpisode.id)!)
    }
    #expect(Set(podcastEpisodes) == Set(fetchedPodcastEpisodes))
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

    // Pin creation dates to a deterministic value so any regression is immediately visible.
    let creationDate = Date(timeIntervalSince1970: 1_234_567)
    try await appDB.db.write { db in
      try Podcast
        .withID(insertedPodcastEpisode.podcast.id)
        .updateAll(db, Podcast.Columns.creationDate.set(to: creationDate))
      try Episode
        .withID(insertedPodcastEpisode.episode.id)
        .updateAll(db, Episode.Columns.creationDate.set(to: creationDate))
    }

    let matchingPodcast = try Create.unsavedPodcast(feedURL: unsavedPodcast.feedURL)
    let matchingEpisode = try Create.unsavedEpisode(mediaURL: unsavedEpisode.mediaURL)

    let updatedPodcastEpisode = try await repo.upsertPodcastEpisode(
      UnsavedPodcastEpisode(
        unsavedPodcast: matchingPodcast,
        unsavedEpisode: matchingEpisode
      )
    )
    #expect(updatedPodcastEpisode.podcast.creationDate == creationDate)
    #expect(updatedPodcastEpisode.episode.creationDate == creationDate)

    let fetchedPodcastEpisode = try await repo.podcastEpisode(updatedPodcastEpisode.id)!
    #expect(fetchedPodcastEpisode.podcast.creationDate == creationDate)
    #expect(fetchedPodcastEpisode.episode.creationDate == creationDate)
  }

  @Test("upsertPodcastEpisode preserves user state when upserting existing records")
  func testUpsertPreservesUserState() async throws {
    // Step 1: Create initial podcast and episode
    let unsavedPodcast = try Create.unsavedPodcast(
      title: "Original Title",
      subscriptionDate: nil
    )
    let unsavedEpisode = try Create.unsavedEpisode(
      title: "Original Episode",
      duration: CMTime.seconds(300)
    )
    let insertedPodcastEpisode = try await repo.upsertPodcastEpisode(
      UnsavedPodcastEpisode(
        unsavedPodcast: unsavedPodcast,
        unsavedEpisode: unsavedEpisode
      )
    )

    // Step 2: Set user state on the inserted records
    let currentTime = CMTime.seconds(120)
    let actualDuration = CMTime.seconds(1800)
    try await repo.markSubscribed(insertedPodcastEpisode.podcast.id)
    try await repo.markFinished(insertedPodcastEpisode.episode.id)
    try await repo.updateCurrentTime(insertedPodcastEpisode.episode.id, currentTime: currentTime)
    try await repo.updateDuration(insertedPodcastEpisode.episode.id, duration: actualDuration)
    try await queue.unshift(insertedPodcastEpisode.episode.id)
    let cachedFilename = "cached.mp3"
    try await repo.updateCachedFilename(
      insertedPodcastEpisode.episode.id,
      cachedFilename: cachedFilename
    )
    let expectedCachedURL = CacheManager.resolveCachedFilepath(for: cachedFilename)

    // Step 3: Upsert with new RSS data but same unique keys
    let updatedUnsavedPodcast = try Create.unsavedPodcast(
      feedURL: unsavedPodcast.feedURL,
      title: "Updated Podcast Title",
      image: URL.valid(),
      description: "Updated podcast description",
      subscriptionDate: nil  // RSS data has no subscription
    )
    let updatedUnsavedEpisode = try Create.unsavedEpisode(
      mediaURL: unsavedEpisode.mediaURL,
      title: "Updated Episode Title",
      pubDate: unsavedEpisode.pubDate,
      duration: CMTime.seconds(600),  // RSS metadata says 600s
      description: "Updated episode description",
      currentTime: .zero,  // RSS data has no current time
      queueOrder: nil  // RSS data has no queue info
    )

    let upsertedPodcastEpisode = try await repo.upsertPodcastEpisode(
      UnsavedPodcastEpisode(
        unsavedPodcast: updatedUnsavedPodcast,
        unsavedEpisode: updatedUnsavedEpisode
      )
    )

    // Step 4: Verify RSS columns were updated
    #expect(upsertedPodcastEpisode.podcast.title == "Updated Podcast Title")
    #expect(upsertedPodcastEpisode.podcast.description == "Updated podcast description")
    #expect(upsertedPodcastEpisode.episode.title == "Updated Episode Title")
    #expect(upsertedPodcastEpisode.episode.description == "Updated episode description")

    // Step 5: Verify user state was preserved (not overwritten by RSS data)
    #expect(upsertedPodcastEpisode.podcast.subscribed == true)
    #expect(upsertedPodcastEpisode.episode.currentTime == currentTime)
    #expect(upsertedPodcastEpisode.episode.finishDate != nil)
    #expect(upsertedPodcastEpisode.episode.queueOrder == 0)
    #expect(upsertedPodcastEpisode.episode.duration == actualDuration)
    #expect(upsertedPodcastEpisode.episode.cachedURL == expectedCachedURL)

    // Step 6: Verify by fetching from database
    let fetchedPodcastEpisode = try await repo.podcastEpisode(upsertedPodcastEpisode.id)!
    #expect(fetchedPodcastEpisode.podcast.subscribed == true)
    #expect(fetchedPodcastEpisode.episode.currentTime == currentTime)
    #expect(fetchedPodcastEpisode.episode.finishDate != nil)
    #expect(fetchedPodcastEpisode.episode.queueOrder == 0)
    #expect(fetchedPodcastEpisode.episode.duration == actualDuration)
    #expect(fetchedPodcastEpisode.episode.cachedURL == expectedCachedURL)
  }

  @Test("upsertPodcastEpisodes preserves creationDate on conflict")
  func testUpsertPreservesCreationDate() async throws {
    let unsavedPodcast = try Create.unsavedPodcast()
    let unsavedEpisode = try Create.unsavedEpisode()
    let insertedPodcastEpisode = try await repo.upsertPodcastEpisode(
      UnsavedPodcastEpisode(
        unsavedPodcast: unsavedPodcast,
        unsavedEpisode: unsavedEpisode
      )
    )

    // Pin creation dates to a known value
    let originalCreationDate = Date(timeIntervalSince1970: 1_000_000)
    try await appDB.db.write { db in
      try Podcast
        .withID(insertedPodcastEpisode.podcast.id)
        .updateAll(db, Podcast.Columns.creationDate.set(to: originalCreationDate))
      try Episode
        .withID(insertedPodcastEpisode.episode.id)
        .updateAll(db, Episode.Columns.creationDate.set(to: originalCreationDate))
    }

    // Upsert with same unique keys but different RSS data
    let updatedUnsavedPodcast = try Create.unsavedPodcast(
      feedURL: unsavedPodcast.feedURL,
      title: "New Title"
    )
    let updatedUnsavedEpisode = try Create.unsavedEpisode(
      mediaURL: unsavedEpisode.mediaURL,
      title: "New Episode Title"
    )

    let upsertedPodcastEpisode = try await repo.upsertPodcastEpisode(
      UnsavedPodcastEpisode(
        unsavedPodcast: updatedUnsavedPodcast,
        unsavedEpisode: updatedUnsavedEpisode
      )
    )

    // creationDate should be preserved (not part of rssUpdatableColumns)
    #expect(upsertedPodcastEpisode.podcast.creationDate == originalCreationDate)
    #expect(upsertedPodcastEpisode.episode.creationDate == originalCreationDate)

    // RSS columns should be updated
    #expect(upsertedPodcastEpisode.podcast.title == "New Title")
    #expect(upsertedPodcastEpisode.episode.title == "New Episode Title")
  }

  @Test("upsertPodcastEpisodes only updates RSS columns on podcast conflict")
  func testUpsertOnlyUpdatesRSSColumnsForPodcast() async throws {
    // Verify that only rssUpdatableColumns are updated during upsert
    let unsavedPodcast = try Create.unsavedPodcast(subscriptionDate: nil)
    let unsavedEpisode = try Create.unsavedEpisode()
    let insertedPodcastEpisode = try await repo.upsertPodcastEpisode(
      UnsavedPodcastEpisode(
        unsavedPodcast: unsavedPodcast,
        unsavedEpisode: unsavedEpisode
      )
    )

    // Subscribe the podcast (user action)
    try await repo.markSubscribed(insertedPodcastEpisode.podcast.id)

    // Upsert with RSS data that would set subscribed=false if all columns updated
    let newUnsavedPodcast = try Create.unsavedPodcast(
      feedURL: unsavedPodcast.feedURL,
      title: "RSS Updated Title",
      subscriptionDate: nil
    )

    let upsertedPodcastEpisode = try await repo.upsertPodcastEpisode(
      UnsavedPodcastEpisode(
        unsavedPodcast: newUnsavedPodcast,
        unsavedEpisode: unsavedEpisode
      )
    )

    // subscribed should remain true (not in rssUpdatableColumns)
    #expect(upsertedPodcastEpisode.podcast.subscribed == true)
    // RSS column should be updated
    #expect(upsertedPodcastEpisode.podcast.title == "RSS Updated Title")
  }

  @Test("upsertPodcastEpisodes only updates RSS columns on episode conflict")
  func testUpsertOnlyUpdatesRSSColumnsForEpisode() async throws {
    let unsavedPodcast = try Create.unsavedPodcast()
    let unsavedEpisode = try Create.unsavedEpisode(
      duration: CMTime.seconds(300)
    )
    let insertedPodcastEpisode = try await repo.upsertPodcastEpisode(
      UnsavedPodcastEpisode(
        unsavedPodcast: unsavedPodcast,
        unsavedEpisode: unsavedEpisode
      )
    )

    // Set user state that is NOT in rssUpdatableColumns
    let userDuration = CMTime.seconds(1800)  // Actual duration from playback
    let currentTime = CMTime.seconds(100)
    try await repo.updateDuration(insertedPodcastEpisode.episode.id, duration: userDuration)
    try await repo.markFinished(insertedPodcastEpisode.episode.id)
    try await repo.updateCurrentTime(insertedPodcastEpisode.episode.id, currentTime: currentTime)

    // Upsert with RSS data that has different values for non-RSS columns
    let newUnsavedEpisode = try Create.unsavedEpisode(
      mediaURL: unsavedEpisode.mediaURL,
      title: "RSS Updated Episode Title",
      duration: CMTime.seconds(600),  // RSS says 600s but user knows it's 1800s
      currentTime: CMTime.seconds(30)  // Will be ignored
    )

    let upsertedPodcastEpisode = try await repo.upsertPodcastEpisode(
      UnsavedPodcastEpisode(
        unsavedPodcast: unsavedPodcast,
        unsavedEpisode: newUnsavedEpisode
      )
    )

    // User state should be preserved (not in rssUpdatableColumns)
    #expect(upsertedPodcastEpisode.episode.duration == userDuration)
    #expect(upsertedPodcastEpisode.episode.currentTime == currentTime)
    #expect(upsertedPodcastEpisode.episode.finishDate != nil)

    // RSS column should be updated
    #expect(upsertedPodcastEpisode.episode.title == "RSS Updated Episode Title")
  }
}
