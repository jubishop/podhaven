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

  private var fileManager: FakeFileManager {
    Container.shared.podFileManager() as! FakeFileManager
  }

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
      mediaURL: MediaURL(URL.valid()),
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
    try await repo.markFinished(originalEpisode.id)
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
        mediaURL: newEpisodeMedia,
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
    #expect(episode.cachedURL == CacheManager.resolveCachedFilepath(for: initialCachedFilename))

    let newCachedFilename = "new-cache.mp3"
    try await repo.updateCachedFilename(episode.id, newCachedFilename)

    let updatedEpisode = try await repo.db.read { db in
      try Episode.fetchOne(db, id: episode.id)
    }!
    #expect(
      updatedEpisode.cachedURL == CacheManager.resolveCachedFilepath(for: newCachedFilename)
    )

    // Test clearing the cached filename (setting to nil)
    try await repo.updateCachedFilename(episode.id, nil)

    let clearedEpisode = try await repo.db.read { db in
      try Episode.fetchOne(db, id: episode.id)
    }!
    #expect(clearedEpisode.cachedURL == nil)
  }

  @Test("that an episode can be marked finished")
  func markEpisodeFinished() async throws {
    let unsavedPodcast = try Create.unsavedPodcast()
    let unsavedEpisode = try Create.unsavedEpisode(currentTime: CMTime.seconds(60))
    let podcastSeries = try await repo.insertSeries(
      unsavedPodcast,
      unsavedEpisodes: [unsavedEpisode]
    )

    let episode = podcastSeries.episodes.first!
    #expect(episode.finished == false)
    #expect(episode.currentTime == CMTime.seconds(60))
    try await repo.markFinished(episode.id)

    let finishedEpisode: Episode? = try await repo.episode(episode.id)!
    #expect(finishedEpisode?.finished == true)
    #expect(finishedEpisode?.currentTime == CMTime.zero)
  }

  @Test("that multiple episodes can be marked finished")
  func markEpisodesFinished() async throws {
    let unsavedPodcast = try Create.unsavedPodcast()
    let unsavedEpisode1 = try Create.unsavedEpisode(currentTime: CMTime.seconds(60))
    let unsavedEpisode2 = try Create.unsavedEpisode(currentTime: CMTime.seconds(120))
    let podcastSeries = try await repo.insertSeries(
      unsavedPodcast,
      unsavedEpisodes: [unsavedEpisode1, unsavedEpisode2]
    )

    let episodes = podcastSeries.episodes
    #expect(episodes.count == 2)
    #expect(episodes.allSatisfy { $0.finished == false })
    #expect(episodes.allSatisfy { $0.currentTime > CMTime.zero })
    try await repo.markFinished(episodes.map(\.id))

    for episode in episodes {
      let finishedEpisode = try await repo.episode(episode.id)!
      #expect(finishedEpisode.finished == true)
      #expect(finishedEpisode.currentTime == CMTime.zero)
    }
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
    #expect(Set(podcastEpisodes.map(\.episode.mediaURL)) == Set(allEpisodes.map(\.mediaURL)))

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
    let matchingEpisode = try Create.unsavedEpisode(mediaURL: unsavedEpisode.mediaURL)

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

  @Test("that episode can be queried by MediaGUID")
  func testEpisodeQueryByMediaGUID() async throws {
    let guid = GUID("test-guid")
    let mediaURL = MediaURL(URL.valid())
    let mediaGUID = MediaGUID(guid: guid, mediaURL: mediaURL)

    let unsavedPodcast = try Create.unsavedPodcast()
    let unsavedEpisode = try Create.unsavedEpisode(
      guid: guid,
      mediaURL: mediaURL,
      title: "Episode with MediaGUID"
    )

    let podcastSeries = try await repo.insertSeries(
      unsavedPodcast,
      unsavedEpisodes: [unsavedEpisode]
    )

    let insertedEpisode = podcastSeries.episodes.first!

    // Query by MediaGUID should return the same episode as query by ID
    let episodeByGUID = try await repo.episode(mediaGUID)
    let episodeByID = try await repo.episode(insertedEpisode.id)

    #expect(episodeByGUID != nil)
    #expect(episodeByID != nil)
    #expect(episodeByGUID?.id == episodeByID?.id)
    #expect(episodeByGUID?.guid == guid)
    #expect(episodeByGUID?.mediaURL == mediaURL)
    #expect(episodeByGUID?.title == "Episode with MediaGUID")
  }

  @Test("that episode query by MediaGUID returns nil for non-existent episode")
  func testEpisodeQueryByMediaGUIDNonExistent() async throws {
    let nonExistentMediaGUID = MediaGUID(
      guid: GUID("non-existent-guid"),
      mediaURL: MediaURL(URL.valid())
    )

    let episode = try await repo.episode(nonExistentMediaGUID)
    #expect(episode == nil)
  }

  @Test("that podcastEpisode can be queried by MediaGUID")
  func testPodcastEpisodeQueryByMediaGUID() async throws {
    let guid = GUID("test-podcast-episode-guid")
    let mediaURL = MediaURL(URL.valid())
    let mediaGUID = MediaGUID(guid: guid, mediaURL: mediaURL)

    let unsavedPodcast = try Create.unsavedPodcast(title: "Test Podcast")
    let unsavedEpisode = try Create.unsavedEpisode(
      guid: guid,
      mediaURL: mediaURL,
      title: "Test Episode"
    )

    let podcastSeries = try await repo.insertSeries(
      unsavedPodcast,
      unsavedEpisodes: [unsavedEpisode]
    )

    let insertedEpisode = podcastSeries.episodes.first!

    // Query by MediaGUID should return the same podcastEpisode as query by ID
    let podcastEpisodeByGUID = try await repo.podcastEpisode(mediaGUID)
    let podcastEpisodeByID = try await repo.podcastEpisode(insertedEpisode.id)

    #expect(podcastEpisodeByGUID != nil)
    #expect(podcastEpisodeByID != nil)
    #expect(podcastEpisodeByGUID?.id == podcastEpisodeByID?.id)
    #expect(podcastEpisodeByGUID?.episode.guid == guid)
    #expect(podcastEpisodeByGUID?.episode.mediaURL == mediaURL)
    #expect(podcastEpisodeByGUID?.episode.title == "Test Episode")
    #expect(podcastEpisodeByGUID?.podcast.title == "Test Podcast")
  }

  @Test("that podcastEpisode query by MediaGUID returns nil for non-existent episode")
  func testPodcastEpisodeQueryByMediaGUIDNonExistent() async throws {
    let nonExistentMediaGUID = MediaGUID(
      guid: GUID("non-existent-podcast-episode-guid"),
      mediaURL: MediaURL(URL.valid())
    )

    let podcastEpisode = try await repo.podcastEpisode(nonExistentMediaGUID)
    #expect(podcastEpisode == nil)
  }

  @Test("that deleting a podcast removes cached episode files")
  func deletePodcastRemovesCachedFiles() async throws {
    let unsavedPodcast = try Create.unsavedPodcast()
    let episode1 = try Create.unsavedEpisode(cachedFilename: "episode-1.mp3")
    let episode2 = try Create.unsavedEpisode(cachedFilename: "episode-2.mp3")
    let series = try await repo.insertSeries(
      unsavedPodcast,
      unsavedEpisodes: [episode1, episode2, Create.unsavedEpisode()]
    )
    let podcast = series.podcast
    let episodes = Array(series.episodes.filter { $0.cacheStatus == .cached })

    // Write files to cached locations
    let fileManager = Container.shared.podFileManager() as! FakeFileManager
    for episode in episodes {
      guard let cachedURL = episode.cachedURL else {
        Assert.fatal("Episode should have cached URL")
      }
      try await fileManager.writeData(Data(UUID().uuidString.utf8), to: cachedURL.rawValue)
      try await CacheHelpers.waitForCachedFile(cachedURL)
    }

    // Delete podcast
    let count = try await repo.delete([podcast.id])
    #expect(count == 1)
    let afterDeletion = try await repo.podcastSeries(podcast.id)
    #expect(afterDeletion == nil)

    // Verify files are removed
    for episode in episodes {
      guard let cachedURL = episode.cachedURL
      else { Assert.fatal("Episode should have cached URL") }
      try await CacheHelpers.waitForCachedFileRemoved(cachedURL)
    }
  }

  @Test("that deletion succeeds when cached file is missing")
  func deletePodcastSucceedsWhenCachedFileMissing() async throws {
    let unsavedPodcast = try Create.unsavedPodcast()
    let episode = try Create.unsavedEpisode(cachedFilename: "missing.mp3")
    let series = try await repo.insertSeries(
      unsavedPodcast,
      unsavedEpisodes: [episode]
    )
    let podcast = series.podcast

    // No file written to the cached location

    // Delete podcast - should succeed even though cached file doesn't exist
    let deletionSucceeded = try await repo.delete(podcast.id)
    #expect(deletionSucceeded == true)

    let afterDeletion = try await repo.podcastSeries(podcast.id)
    #expect(afterDeletion == nil)
  }

  @Test("that MediaGUID queries are consistent across multiple episodes")
  func testMediaGUIDQueriesConsistency() async throws {
    let unsavedPodcast = try Create.unsavedPodcast()

    let episode1GUID = GUID("episode-1")
    let episode1Media = MediaURL(URL.valid())
    let episode1MediaGUID = MediaGUID(guid: episode1GUID, mediaURL: episode1Media)

    let episode2GUID = GUID("episode-2")
    let episode2Media = MediaURL(URL.valid())
    let episode2MediaGUID = MediaGUID(guid: episode2GUID, mediaURL: episode2Media)

    let unsavedEpisode1 = try Create.unsavedEpisode(
      guid: episode1GUID,
      mediaURL: episode1Media,
      title: "Episode 1"
    )
    let unsavedEpisode2 = try Create.unsavedEpisode(
      guid: episode2GUID,
      mediaURL: episode2Media,
      title: "Episode 2"
    )

    try await repo.insertSeries(
      unsavedPodcast,
      unsavedEpisodes: [unsavedEpisode1, unsavedEpisode2]
    )

    // Test that each MediaGUID returns the correct episode
    let foundEpisode1 = try await repo.episode(episode1MediaGUID)
    let foundEpisode2 = try await repo.episode(episode2MediaGUID)

    #expect(foundEpisode1 != nil)
    #expect(foundEpisode2 != nil)
    #expect(foundEpisode1?.title == "Episode 1")
    #expect(foundEpisode2?.title == "Episode 2")
    #expect(foundEpisode1?.guid == episode1GUID)
    #expect(foundEpisode2?.guid == episode2GUID)
    #expect(foundEpisode1?.mediaURL == episode1Media)
    #expect(foundEpisode2?.mediaURL == episode2Media)

    // Test with podcastEpisode queries as well
    let foundPodcastEpisode1 = try await repo.podcastEpisode(episode1MediaGUID)
    let foundPodcastEpisode2 = try await repo.podcastEpisode(episode2MediaGUID)

    #expect(foundPodcastEpisode1 != nil)
    #expect(foundPodcastEpisode2 != nil)
    #expect(foundPodcastEpisode1?.episode.title == "Episode 1")
    #expect(foundPodcastEpisode2?.episode.title == "Episode 2")
  }

  @Test("update and fetch episode by downloadTaskID")
  func updateAndFetchByTaskID() async throws {
    // Create two episodes
    let (one, two) = try await Create.twoPodcastEpisodes()

    let id1 = URLSessionDownloadTask.ID(101)
    let id2 = URLSessionDownloadTask.ID(202)

    // Set mapping for first
    let updated1 = try await repo.updateDownloadTaskID(one.id, id1)
    #expect(updated1)

    // Fetch by single task id
    let fetched1 = try await repo.episode(id1)
    #expect(fetched1 != nil)
    #expect(fetched1?.id == one.id)

    // Set mapping for second and verify batch fetch
    let updated2 = try await repo.updateDownloadTaskID(two.id, id2)
    #expect(updated2)

    let fetchedBatch = try await repo.episodes([id1, id2])
    #expect(fetchedBatch.count == 2)
    let fetchedIDs = Set(fetchedBatch.map(\.id))
    #expect(fetchedIDs == Set([one.id, two.id]))

    // Clear first mapping and verify lookup is nil
    _ = try await repo.updateDownloadTaskID(one.id, nil)
    let shouldBeNil = try await repo.episode(id1)
    #expect(shouldBeNil == nil)
  }

  @Test("unique constraint enforced when assigning duplicate downloadTaskID")
  func uniqueConstraintOnTaskID() async throws {
    let (one, two) = try await Create.twoPodcastEpisodes()
    let sharedID = URLSessionDownloadTask.ID(4242)

    _ = try await repo.updateDownloadTaskID(one.id, sharedID)

    await #expect(throws: DatabaseError.self) {
      _ = try await self.repo.updateDownloadTaskID(two.id, sharedID)
    }
  }

  @Test("episodes([]) returns empty array")
  func episodesEmptyBatch() async throws {
    let results = try await repo.episodes([])
    #expect(results.isEmpty)
  }

  @Test("cachedEpisodes returns only episodes with cached files")
  func cachedEpisodesReturnsOnlyCachedEpisodes() async throws {
    let unsavedPodcast = try Create.unsavedPodcast()

    // Create episodes with cached files
    let cachedEpisode1 = try Create.unsavedEpisode(
      title: "Cached Episode 1",
      cachedFilename: "episode-1.mp3"
    )
    let cachedEpisode2 = try Create.unsavedEpisode(
      title: "Cached Episode 2",
      cachedFilename: "episode-2.mp3"
    )

    // Create episodes without cached files
    let uncachedEpisode1 = try Create.unsavedEpisode(title: "Uncached Episode 1")
    let uncachedEpisode2 = try Create.unsavedEpisode(title: "Uncached Episode 2")

    _ = try await repo.insertSeries(
      unsavedPodcast,
      unsavedEpisodes: [cachedEpisode1, uncachedEpisode1, cachedEpisode2, uncachedEpisode2]
    )

    // Fetch cached episodes
    let cachedEpisodes = try await repo.cachedEpisodes()

    // Verify only cached episodes are returned
    #expect(cachedEpisodes.count == 2)
    let cachedTitles = Set(cachedEpisodes.map(\.title))
    #expect(cachedTitles == Set(["Cached Episode 1", "Cached Episode 2"]))

    // Verify all returned episodes have cached status
    #expect(cachedEpisodes.allSatisfy { $0.cacheStatus == .cached })
  }

  @Test("cachedEpisodes includes queued cached episodes")
  func cachedEpisodesIncludesQueuedEpisodes() async throws {
    let unsavedPodcast = try Create.unsavedPodcast()

    // Create cached episodes
    let cachedEpisode1 = try Create.unsavedEpisode(
      title: "Cached Unqueued",
      cachedFilename: "episode-1.mp3"
    )
    let cachedEpisode2 = try Create.unsavedEpisode(
      title: "Cached Queued",
      cachedFilename: "episode-2.mp3"
    )

    let podcastSeries = try await repo.insertSeries(
      unsavedPodcast,
      unsavedEpisodes: [cachedEpisode1, cachedEpisode2]
    )

    // Queue one of the cached episodes
    try await queue.unshift(podcastSeries.episodes[1].id)

    // Fetch cached episodes
    let cachedEpisodes = try await repo.cachedEpisodes()

    // Verify both cached episodes are returned (queued and unqueued)
    #expect(cachedEpisodes.count == 2)
    let cachedTitles = Set(cachedEpisodes.map(\.title))
    #expect(cachedTitles == Set(["Cached Unqueued", "Cached Queued"]))
  }

  @Test("cachedEpisodes returns empty array when no episodes are cached")
  func cachedEpisodesReturnsEmptyWhenNoCachedEpisodes() async throws {
    let unsavedPodcast = try Create.unsavedPodcast()
    let uncachedEpisode1 = try Create.unsavedEpisode()
    let uncachedEpisode2 = try Create.unsavedEpisode()

    try await repo.insertSeries(
      unsavedPodcast,
      unsavedEpisodes: [uncachedEpisode1, uncachedEpisode2]
    )

    let cachedEpisodes = try await repo.cachedEpisodes()

    #expect(cachedEpisodes.isEmpty)
  }
}
