// Copyright Justin Bishop, 2025

import AVFoundation
import FactoryKit
import FactoryTesting
import Foundation
import GRDB
import Testing

@testable import PodHaven

@Suite("Episode persistence tests", .container)
class EpisodePersistenceTests {
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
      UnsavedPodcastSeries(
        unsavedPodcast: unsavedPodcast,
        unsavedEpisodes: [
          middleUnsavedEpisode,
          ancientUnsavedEpisode,
          oldUnsavedEpisode,
          newestUnsavedEpisode,
        ]
      )
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

  @Test("that episode GUID can be updated")
  func guidUpdateAllowed() async throws {
    let unsavedPodcast = try Create.unsavedPodcast()
    let unsavedEpisode = try Create.unsavedEpisode(guid: GUID("original-guid"))
    let podcastSeries = try await repo.insertSeries(
      UnsavedPodcastSeries(
        unsavedPodcast: unsavedPodcast,
        unsavedEpisodes: [unsavedEpisode]
      )
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
      UnsavedPodcastSeries(
        unsavedPodcast: unsavedPodcast,
        unsavedEpisodes: [unsavedEpisode]
      )
    )
    let podcast = podcastSeries.podcast

    let episode = try await repo.db.read { db in
      try Episode.fetchOne(db, key: ["guid": guid, "podcastId": podcast.id])
    }!
    #expect(episode.currentTime == cmTime)

    let newCMTime = CMTime.seconds(60)
    try await repo.updateCurrentTime(episode.id, currentTime: newCMTime)

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
      UnsavedPodcastSeries(
        unsavedPodcast: unsavedPodcast,
        unsavedEpisodes: [unsavedEpisode]
      )
    )
    let podcast = podcastSeries.podcast

    let episode = try await repo.db.read { db in
      try Episode.fetchOne(db, key: ["guid": guid, "podcastId": podcast.id])
    }!
    #expect(episode.duration == cmTime)

    let newCMTime = CMTime.seconds(60)
    try await repo.updateDuration(episode.id, duration: newCMTime)

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
      UnsavedPodcastSeries(
        unsavedPodcast: unsavedPodcast,
        unsavedEpisodes: [unsavedEpisode]
      )
    )
    let podcast = podcastSeries.podcast

    let episode = try await repo.db.read { db in
      try Episode.fetchOne(db, key: ["guid": guid, "podcastId": podcast.id])
    }!
    #expect(episode.cachedURL == CacheManager.resolveCachedFilepath(for: initialCachedFilename))

    let newCachedFilename = "new-cache.mp3"
    try await repo.updateCachedFilename(episode.id, cachedFilename: newCachedFilename)

    let updatedEpisode = try await repo.db.read { db in
      try Episode.fetchOne(db, id: episode.id)
    }!
    #expect(
      updatedEpisode.cachedURL == CacheManager.resolveCachedFilepath(for: newCachedFilename)
    )

    // Test clearing the cached filename (setting to nil)
    try await repo.updateCachedFilename(episode.id, cachedFilename: nil)

    let clearedEpisode = try await repo.db.read { db in
      try Episode.fetchOne(db, id: episode.id)
    }!
    #expect(clearedEpisode.cachedURL == nil)
  }

  @Test("that episodes can persist saveInCache")
  func persistSaveInCache() async throws {
    let guid = GUID("guid")

    let unsavedPodcast = try Create.unsavedPodcast()
    let unsavedEpisode = try Create.unsavedEpisode(guid: guid, saveInCache: false)
    let podcastSeries = try await repo.insertSeries(
      UnsavedPodcastSeries(
        unsavedPodcast: unsavedPodcast,
        unsavedEpisodes: [unsavedEpisode]
      )
    )
    let podcast = podcastSeries.podcast

    let episode = try await repo.db.read { db in
      try Episode.fetchOne(db, key: ["guid": guid, "podcastId": podcast.id])
    }!
    #expect(episode.saveInCache == false)

    try await repo.updateSaveInCache(episode.id, saveInCache: true)

    let updatedEpisode = try await repo.db.read { db in
      try Episode.fetchOne(db, id: episode.id)
    }!
    #expect(updatedEpisode.saveInCache == true)

    try await repo.updateSaveInCache(episode.id, saveInCache: false)

    let reUpdatedEpisode = try await repo.db.read { db in
      try Episode.fetchOne(db, id: episode.id)
    }!
    #expect(reUpdatedEpisode.saveInCache == false)
  }

  @Test("that an episode can be marked finished")
  func markEpisodeFinished() async throws {
    let unsavedPodcast = try Create.unsavedPodcast()
    let unsavedEpisode = try Create.unsavedEpisode(currentTime: CMTime.seconds(60))
    let podcastSeries = try await repo.insertSeries(
      UnsavedPodcastSeries(
        unsavedPodcast: unsavedPodcast,
        unsavedEpisodes: [unsavedEpisode]
      )
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
      UnsavedPodcastSeries(
        unsavedPodcast: unsavedPodcast,
        unsavedEpisodes: [unsavedEpisode1, unsavedEpisode2]
      )
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

  @Test("that insertSeries adds creationDates")
  func testInsertSeriesCreationDate() async throws {
    let creationDate = Date()
    let unsavedPodcast = try Create.unsavedPodcast()
    let unsavedEpisodes = try [Create.unsavedEpisode(), Create.unsavedEpisode()]
    let series = try await repo.insertSeries(
      UnsavedPodcastSeries(unsavedPodcast: unsavedPodcast, unsavedEpisodes: unsavedEpisodes)
    )

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

  @Test("toOriginalUnsavedEpisode resets all user-generated fields")
  func toOriginalUnsavedEpisodeResetsUserFields() throws {
    let unsavedEpisode = try Create.unsavedEpisode(
      currentTime: CMTime.seconds(120),
      queueOrder: 5,
      queueDate: Date(),
      cachedFilename: "cached.mp3"
    )

    let original = try unsavedEpisode.toOriginalUnsavedEpisode()

    #expect(original.finishDate == nil)
    #expect(original.currentTime == .zero)
    #expect(original.queueOrder == nil)
    #expect(original.queueDate == nil)
    #expect(original.cachedURL == nil)
    #expect(original.downloadTaskID == nil)

    // Feed fields should be preserved
    #expect(original.guid == unsavedEpisode.guid)
    #expect(original.mediaURL == unsavedEpisode.mediaURL)
    #expect(original.title == unsavedEpisode.title)
    #expect(original.pubDate == unsavedEpisode.pubDate)
    #expect(original.duration == unsavedEpisode.duration)
    #expect(original.description == unsavedEpisode.description)
    #expect(original.link == unsavedEpisode.link)
    #expect(original.image == unsavedEpisode.image)
  }

  @Test("that inserting duplicate episodes across feeds throws duplicateConflict")
  func insertDuplicateEpisodesThrowsDuplicateConflict() async throws {
    let sharedGUID = GUID("shared-guid")
    let sharedMediaURL = MediaURL(URL.valid())

    // Insert first podcast with an episode
    let firstPodcast = try Create.unsavedPodcast()
    let firstEpisode = try Create.unsavedEpisode(guid: sharedGUID, mediaURL: sharedMediaURL)
    try await repo.insertSeries(
      UnsavedPodcastSeries(unsavedPodcast: firstPodcast, unsavedEpisodes: [firstEpisode])
    )

    // Try to insert second podcast with an episode that has the same guid+mediaURL
    let secondPodcast = try Create.unsavedPodcast()
    let duplicateEpisode = try Create.unsavedEpisode(guid: sharedGUID, mediaURL: sharedMediaURL)
    let secondSeries = UnsavedPodcastSeries(
      unsavedPodcast: secondPodcast,
      unsavedEpisodes: [duplicateEpisode]
    )

    do {
      try await repo.insertSeries(secondSeries)
      Issue.record("Expected duplicateConflict error to be thrown")
    } catch let error {
      guard case .duplicateConflict(let errorSeries, _) = error else {
        Issue.record("Expected duplicateConflict but got \(error)")
        return
      }
      #expect(errorSeries.unsavedPodcast.feedURL == secondSeries.unsavedPodcast.feedURL)
      #expect(errorSeries.unsavedEpisodes.count == secondSeries.unsavedEpisodes.count)
    }
  }
}
