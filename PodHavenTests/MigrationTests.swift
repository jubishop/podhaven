// Copyright Justin Bishop, 2025

import FactoryKit
import FactoryTesting
import Foundation
import GRDB
import Testing

@testable import PodHaven

@Suite("of Migration tests", .container)
class MigrationTests {
  private let appDB = AppDB.inMemory(migrate: false)
  private let migrator: DatabaseMigrator

  init() async throws {
    self.migrator = try Schema.makeMigrator()
  }

  @Test("migrating to v15, adding unique constraint on guid+media combination")
  func testV15Migration() async throws {
    try migrator.migrate(appDB.db, upTo: "v1")

    // Insert test data in v14 schema with some duplicate guid+media combinations
    let now = Date()
    let yesterday = 24.hoursAgo

    let (podcast1Id, podcast2Id, episode1Id, episode2Id, episode3Id, episode4Id) =
      try await appDB.db.write { db in
        // Create two podcasts
        try db.execute(
          sql: """
            INSERT INTO podcast (feedURL, title, image, description, subscriptionDate, cacheAllEpisodes)
            VALUES ('https://example1.com/feed.xml', 'Podcast 1', 'https://example1.com/image.jpg', 'Description 1', ?, ?)
            """,
          arguments: [now, false]
        )
        let podcast1Id = db.lastInsertedRowID

        try db.execute(
          sql: """
            INSERT INTO podcast (feedURL, title, image, description, subscriptionDate, cacheAllEpisodes)
            VALUES ('https://example2.com/feed.xml', 'Podcast 2', 'https://example2.com/image.jpg', 'Description 2', ?, ?)
            """,
          arguments: [yesterday, true]
        )
        let podcast2Id = db.lastInsertedRowID

        // Create episodes - some with duplicate guid+media combinations across podcasts
        // Episode 1 in Podcast 1 - unique
        try db.execute(
          sql: """
            INSERT INTO episode (podcastId, guid, media, title, pubDate, duration, currentTime)
            VALUES (?, 'unique-guid-1', 'https://example.com/unique1.mp3', 'Unique Episode 1', ?, ?, ?)
            """,
          arguments: [podcast1Id, yesterday, 1800, 0]
        )
        let episode1Id = db.lastInsertedRowID

        // Episode 2 in Podcast 1 - will have same guid+media as episode 3
        try db.execute(
          sql: """
            INSERT INTO episode (podcastId, guid, media, title, pubDate, duration, currentTime)
            VALUES (?, 'duplicate-guid', 'https://example.com/duplicate.mp3', 'Original Episode', ?, ?, ?)
            """,
          arguments: [podcast1Id, yesterday, 2400, 300]
        )
        let episode2Id = db.lastInsertedRowID

        // Episode 3 in Podcast 2 - same guid+media as Episode 2 (creates duplicate across podcasts)
        try db.execute(
          sql: """
            INSERT INTO episode (podcastId, guid, media, title, pubDate, duration, currentTime, cachedFilename)
            VALUES (?, 'duplicate-guid', 'https://example.com/duplicate.mp3', 'Duplicate Episode', ?, ?, ?, ?)
            """,
          arguments: [podcast2Id, now, 1200, 600, "cached.mp3"]
        )
        let episode3Id = db.lastInsertedRowID

        // Episode 4 in Podcast 1 - unique
        try db.execute(
          sql: """
            INSERT INTO episode (podcastId, guid, media, title, pubDate, duration, currentTime)
            VALUES (?, 'unique-guid-2', 'https://example.com/unique2.mp3', 'Unique Episode 2', ?, ?, ?)
            """,
          arguments: [podcast1Id, now, 900, 450]
        )
        let episode4Id = db.lastInsertedRowID

        return (podcast1Id, podcast2Id, episode1Id, episode2Id, episode3Id, episode4Id)
      }

    // Verify we have the expected episodes before migration
    try await appDB.db.read { db in
      let episodeCount = try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM episode")!
      #expect(episodeCount == 4, "Should have 4 episodes before migration")

      // Verify we have duplicate guid+media combinations
      let duplicateCount = try Int.fetchOne(
        db,
        sql: """
          SELECT COUNT(*) FROM (
            SELECT guid, media, COUNT(*) as count
            FROM episode 
            GROUP BY guid, media 
            HAVING COUNT(*) > 1
          )
          """
      )!
      #expect(
        duplicateCount == 1,
        "Should have 1 duplicate guid+media combination before migration"
      )
    }

    // Verify unique constraint doesn't exist before migration
    try await appDB.db.read { db in
      let indexes = try Row.fetchAll(
        db,
        sql:
          "SELECT name FROM sqlite_master WHERE type = 'index' AND name = 'episode_on_guid_media'"
      )
      #expect(indexes.isEmpty, "episode_on_guid_media index should not exist before migration")
    }

    // Migrate to v15
    try migrator.migrate(appDB.db, upTo: "v15")

    // Verify the migration results
    try await appDB.db.read { db in
      // Verify unique index was created
      let indexes = try Row.fetchAll(
        db,
        sql:
          "SELECT name FROM sqlite_master WHERE type = 'index' AND name = 'episode_on_guid_media'"
      )
      #expect(indexes.count == 1, "episode_on_guid_media unique index should exist after migration")

      // Verify duplicates were removed - should now have 3 episodes instead of 5
      let episodeCount = try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM episode")!
      #expect(episodeCount == 3, "Should have 3 episodes after removing duplicates")

      // Verify no duplicate guid+media combinations remain
      let duplicateCount = try Int.fetchOne(
        db,
        sql: """
          SELECT COUNT(*) FROM (
            SELECT guid, media, COUNT(*) as count
            FROM episode 
            GROUP BY guid, media 
            HAVING COUNT(*) > 1
          )
          """
      )!
      #expect(
        duplicateCount == 0,
        "Should have no duplicate guid+media combinations after migration"
      )

      // Verify which episodes were kept (should be the ones with lowest IDs)
      let remainingEpisodes = try Row.fetchAll(
        db,
        sql: "SELECT id, guid, media, title FROM episode ORDER BY id"
      )

      #expect(remainingEpisodes.count == 3, "Should have exactly 3 remaining episodes")

      // Episode 1 should remain (unique)
      let episode1 = remainingEpisodes[0]
      #expect(episode1["id"] as! Int64 == episode1Id, "Episode 1 should remain")
      #expect(episode1["guid"] as! String == "unique-guid-1", "Episode 1 should have correct guid")

      // Episode 2 should remain (oldest duplicate)
      let episode2 = remainingEpisodes[1]
      #expect(episode2["id"] as! Int64 == episode2Id, "Episode 2 should remain (oldest duplicate)")
      #expect(episode2["guid"] as! String == "duplicate-guid", "Episode 2 should have correct guid")
      #expect(
        episode2["title"] as! String == "Original Episode",
        "Episode 2 should be the original"
      )

      // Episode 4 should remain (unique)
      let episode4 = remainingEpisodes[2]
      #expect(episode4["id"] as! Int64 == episode4Id, "Episode 4 should remain")
      #expect(episode4["guid"] as! String == "unique-guid-2", "Episode 4 should have correct guid")

      // Episode 3 should be deleted (duplicate)
      let episode3Exists = try Row.fetchOne(
        db,
        sql: "SELECT id FROM episode WHERE id = ?",
        arguments: [episode3Id]
      )
      #expect(episode3Exists == nil, "Episode 3 should be deleted (duplicate)")
    }

    // Test that the unique constraint is enforced after migration
    try await appDB.db.write { db in
      // This should succeed - new unique combination
      try db.execute(
        sql: """
          INSERT INTO episode (podcastId, guid, media, title, pubDate, duration, currentTime)
          VALUES (?, 'new-unique-guid', 'https://example.com/new-unique.mp3', 'New Unique Episode', ?, ?, ?)
          """,
        arguments: [podcast1Id, now, 1500, 0]
      )
    }

    // Verify the new episode was inserted
    try await appDB.db.read { db in
      let episodeCount = try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM episode")!
      #expect(episodeCount == 4, "Should have 4 episodes after inserting new unique episode")
    }

    // Test that duplicate insertion fails
    await #expect(throws: DatabaseError.self) {
      try await self.appDB.db.write { db in
        // This should fail - duplicate guid+media combination
        try db.execute(
          sql: """
            INSERT INTO episode (podcastId, guid, media, title, pubDate, duration, currentTime)
            VALUES (?, 'duplicate-guid', 'https://example.com/duplicate.mp3', 'Should Fail', ?, ?, ?)
            """,
          arguments: [podcast2Id, now, 1800, 0]
        )
      }
    }

    // Verify episode count didn't change after failed insert
    try await appDB.db.read { db in
      let episodeCount = try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM episode")!
      #expect(episodeCount == 4, "Episode count should remain 4 after failed duplicate insert")
    }

    // Test that same GUID with different media URL works
    // Note: after migration, podcast2 no longer has duplicate-guid (it was deleted)
    // so we can insert duplicate-guid into podcast2 with different media
    try await appDB.db.write { db in
      try db.execute(
        sql: """
          INSERT INTO episode (podcastId, guid, media, title, pubDate, duration, currentTime)
          VALUES (?, 'duplicate-guid', 'https://example.com/different-media.mp3', 'Same GUID Different Media', ?, ?, ?)
          """,
        arguments: [podcast2Id, now, 2100, 0]
      )
    }

    // Test that different GUID with same media URL works
    try await appDB.db.write { db in
      try db.execute(
        sql: """
          INSERT INTO episode (podcastId, guid, media, title, pubDate, duration, currentTime)
          VALUES (?, 'different-guid', 'https://example.com/duplicate.mp3', 'Different GUID Same Media', ?, ?, ?)
          """,
        arguments: [podcast2Id, now, 1900, 0]
      )
    }

    // Verify both episodes were inserted
    try await appDB.db.read { db in
      let episodeCount = try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM episode")!
      #expect(
        episodeCount == 6,
        "Should have 6 episodes after inserting episodes with partial matches"
      )

      // Verify we still have no duplicate guid+media combinations
      let duplicateCount = try Int.fetchOne(
        db,
        sql: """
          SELECT COUNT(*) FROM (
            SELECT guid, media, COUNT(*) as count
            FROM episode 
            GROUP BY guid, media 
            HAVING COUNT(*) > 1
          )
          """
      )!
      #expect(duplicateCount == 0, "Should still have no duplicate guid+media combinations")
    }
  }

  @Test("v16 adds downloadTaskID column and unique index")
  func testV16AddsColumnAndIndex() async throws {
    // Up to v15: column and index should not exist
    try migrator.migrate(appDB.db, upTo: "v15")

    try await appDB.db.read { db in
      // Verify column does not exist yet
      let cols = try Row.fetchAll(db, sql: "PRAGMA table_info('episode')")
      let colNames = Set(cols.compactMap { $0["name"] as? String })
      #expect(!colNames.contains("downloadTaskID"))

      // Verify unique index does not exist yet
      let idxRows = try Row.fetchAll(
        db,
        sql:
          "SELECT name FROM sqlite_master WHERE type = 'index' AND name = 'episode_on_downloadTaskID'"
      )
      #expect(idxRows.isEmpty)
    }

    // Migrate to v16
    try migrator.migrate(appDB.db, upTo: "v16")

    try await appDB.db.read { db in
      // Verify column exists
      let cols = try Row.fetchAll(db, sql: "PRAGMA table_info('episode')")
      let colNames = Set(cols.compactMap { $0["name"] as? String })
      #expect(colNames.contains("downloadTaskID"))

      // Verify unique index exists
      let idxRows = try Row.fetchAll(
        db,
        sql:
          "SELECT name FROM sqlite_master WHERE type = 'index' AND name = 'episode_on_downloadTaskID'"
      )
      #expect(idxRows.count == 1)
    }
  }

  @Test("v16 enforces uniqueness of downloadTaskID and allows multiple NULLs")
  func testV16UniqueConstraint() async throws {
    try migrator.migrate(appDB.db, upTo: "v16")

    // Create a podcast to satisfy FK
    let podcastID: Int64 = try await appDB.db.write { db in
      try db.execute(
        sql: """
          INSERT INTO podcast (feedURL, title, image, description)
          VALUES ('https://example.com/feed.xml', 'P', 'https://example.com/image.jpg', 'D')
          """
      )
      return db.lastInsertedRowID
    }

    // Insert two with NULL downloadTaskID (allowed)
    try await appDB.db.write { db in
      try db.execute(
        sql: """
          INSERT INTO episode (
            podcastId, guid, media, title, pubDate, duration, currentTime, downloadTaskID
          ) VALUES (?, ?, ?, ?, CURRENT_TIMESTAMP, 0, 0, NULL)
          """,
        arguments: [podcastID, "n1", "https://e.com/n1.mp3", "N1"]
      )
      try db.execute(
        sql: """
          INSERT INTO episode (
            podcastId, guid, media, title, pubDate, duration, currentTime, downloadTaskID
          ) VALUES (?, ?, ?, ?, CURRENT_TIMESTAMP, 0, 0, NULL)
          """,
        arguments: [podcastID, "n2", "https://e.com/n2.mp3", "N2"]
      )
    }

    // Insert one with a non-null downloadTaskID
    try await appDB.db.write { db in
      try db.execute(
        sql: """
          INSERT INTO episode (
            podcastId, guid, media, title, pubDate, duration, currentTime, downloadTaskID
          ) VALUES (?, ?, ?, ?, CURRENT_TIMESTAMP, 0, 0, ?)
          """,
        arguments: [podcastID, "u1", "https://e.com/u1.mp3", "U1", 777]
      )
    }

    // Attempt to insert another with same downloadTaskID should fail
    await #expect(throws: DatabaseError.self) {
      try await self.appDB.db.write { db in
        try db.execute(
          sql: """
            INSERT INTO episode (
              podcastId, guid, media, title, pubDate, duration, currentTime, downloadTaskID
            ) VALUES (?, ?, ?, ?, CURRENT_TIMESTAMP, 0, 0, ?)
            """,
          arguments: [podcastID, "u2", "https://e.com/u2.mp3", "U2", 777]
        )
      }
    }
  }

//  @Test("v17 migration renames media column to mediaURL")
//  func testV17MediaToMediaURLMigration() async throws {
//    // Apply migrations up to v16
//    try migrator.migrate(appDB.db, upTo: "v16")
//
//    // Insert test data using the old schema
//    let testPodcastID = try await appDB.db.write { db in
//      try db.execute(
//        sql: """
//          INSERT INTO podcast (feedURL, title, image, description, lastUpdate, creationDate)
//          VALUES (?, ?, ?, ?, ?, ?)
//          """,
//        arguments: [
//          "https://example.com/feed.xml",
//          "Test Podcast",
//          "https://example.com/image.jpg",
//          "Test Description",
//          Date(),
//          Date(),
//        ]
//      )
//      return db.lastInsertedRowID
//    }
//
//    let testMediaURL = "https://example.com/episode.mp3"
//    let testGUID = "test-episode-guid"
//    let testTitle = "Test Episode"
//    let testPubDate = Date()
//    let testDuration: Int64 = 1800  // 30 minutes in seconds
//
//    try await appDB.db.write { db in
//      try db.execute(
//        sql: """
//          INSERT INTO episode (
//            podcastId, guid, media, title, pubDate, duration, currentTime, creationDate
//          ) VALUES (?, ?, ?, ?, ?, ?, ?, ?)
//          """,
//        arguments: [
//          testPodcastID,
//          testGUID,
//          testMediaURL,
//          testTitle,
//          testPubDate,
//          testDuration,
//          0,
//          Date(),
//        ]
//      )
//    }
//
//    // Verify data exists with old column name
//    let oldEpisodeData = try await appDB.db.read { db in
//      try Row.fetchOne(
//        db,
//        sql: "SELECT podcastId, guid, media, title, pubDate, duration FROM episode WHERE guid = ?",
//        arguments: [testGUID]
//      )
//    }
//    #expect(oldEpisodeData != nil)
//    #expect(oldEpisodeData!["media"] as String == testMediaURL)
//
//    // Apply v17 migration
//    try migrator.migrate(appDB.db, upTo: "v17")
//
//    // Verify data exists with new column name
//    let newEpisodeData = try await appDB.db.read { db in
//      try Row.fetchOne(
//        db,
//        sql:
//          "SELECT podcastId, guid, mediaURL, title, pubDate, duration FROM episode WHERE guid = ?",
//        arguments: [testGUID]
//      )
//    }
//    #expect(newEpisodeData != nil)
//    #expect(newEpisodeData!["mediaURL"] as String == testMediaURL)
//    #expect(newEpisodeData!["title"] as String == testTitle)
//    #expect(newEpisodeData!["duration"] as Int64 == testDuration)
//
//    // Verify old column no longer exists
//    await #expect(throws: DatabaseError.self) {
//      try await self.appDB.db.read { db in
//        try Row.fetchOne(
//          db,
//          sql: "SELECT media FROM episode WHERE guid = ?",
//          arguments: [testGUID]
//        )
//      }
//    }
//  }
//
//  @Test("v17 migration preserves all data and constraints")
//  func testV17MigrationPreservesDataAndConstraints() async throws {
//    // Apply migrations up to v16
//    try migrator.migrate(appDB.db, upTo: "v16")
//
//    // Insert multiple test records
//    let testData = [
//      (
//        "podcast1", "https://example1.com/feed.xml", "guid1", "https://example1.com/ep1.mp3",
//        "Episode 1"
//      ),
//      (
//        "podcast2", "https://example2.com/feed.xml", "guid2", "https://example2.com/ep2.mp3",
//        "Episode 2"
//      ),
//      (
//        "podcast3", "https://example3.com/feed.xml", "guid3", "https://example3.com/ep3.mp3",
//        "Episode 3"
//      ),
//    ]
//
//    var podcastEpisodePairs: [(Int64, String, String)] = []
//
//    for (podcastTitle, feedURL, guid, mediaURL, episodeTitle) in testData {
//      let podcastID = try await appDB.db.write { db in
//        try db.execute(
//          sql: """
//            INSERT INTO podcast (feedURL, title, image, description, lastUpdate, creationDate)
//            VALUES (?, ?, ?, ?, ?, ?)
//            """,
//          arguments: [
//            feedURL, podcastTitle, "https://example.com/image.jpg", "Description", Date(), Date(),
//          ]
//        )
//        return db.lastInsertedRowID
//      }
//
//      try await appDB.db.write { db in
//        try db.execute(
//          sql: """
//            INSERT INTO episode (
//              podcastId, guid, media, title, pubDate, currentTime, creationDate
//            ) VALUES (?, ?, ?, ?, ?, ?, ?)
//            """,
//          arguments: [podcastID, guid, mediaURL, episodeTitle, Date(), 0, Date()]
//        )
//      }
//
//      podcastEpisodePairs.append((podcastID, guid, mediaURL))
//    }
//
//    // Apply v17 migration
//    try migrator.migrate(appDB.db, upTo: "v17")
//
//    // Verify all data is preserved
//    for (podcastID, guid, expectedMediaURL) in podcastEpisodePairs {
//      let episodeData = try await appDB.db.read { db in
//        try Row.fetchOne(
//          db,
//          sql: """
//            SELECT e.podcastId, e.guid, e.mediaURL, e.title, p.title as podcastTitle
//            FROM episode e
//            JOIN podcast p ON e.podcastId = p.id
//            WHERE e.guid = ?
//            """,
//          arguments: [guid]
//        )
//      }
//
//      #expect(episodeData != nil)
//      #expect(episodeData!["podcastId"] as Int64 == podcastID)
//      #expect(episodeData!["guid"] as String == guid)
//      #expect(episodeData!["mediaURL"] as String == expectedMediaURL)
//    }
//
//    // Verify unique constraint on podcastId + guid still works
//    await #expect(throws: DatabaseError.self) {
//      try await self.appDB.db.write { db in
//        try db.execute(
//          sql: """
//            INSERT INTO episode (
//              podcastId, guid, mediaURL, title, pubDate, currentTime, creationDate
//            ) VALUES (?, ?, ?, ?, ?, ?, ?)
//            """,
//          arguments: [
//            podcastEpisodePairs[0].0, podcastEpisodePairs[0].1, "https://different.com/url.mp3",
//            "Different Episode", Date(), 0, Date(),
//          ]
//        )
//      }
//    }
//
//    // Verify unique constraint on podcastId + mediaURL works
//    await #expect(throws: DatabaseError.self) {
//      try await self.appDB.db.write { db in
//        try db.execute(
//          sql: """
//            INSERT INTO episode (
//              podcastId, guid, mediaURL, title, pubDate, currentTime, creationDate
//            ) VALUES (?, ?, ?, ?, ?, ?, ?)
//            """,
//          arguments: [
//            podcastEpisodePairs[0].0, "different-guid", podcastEpisodePairs[0].2,
//            "Different Episode", Date(), 0, Date(),
//          ]
//        )
//      }
//    }
//
//    // Verify unique constraint on guid + mediaURL works
//    await #expect(throws: DatabaseError.self) {
//      try await self.appDB.db.write { db in
//        try db.execute(
//          sql: """
//            INSERT INTO episode (
//              podcastId, guid, mediaURL, title, pubDate, currentTime, creationDate
//            ) VALUES (?, ?, ?, ?, ?, ?, ?)
//            """,
//          arguments: [
//            podcastEpisodePairs[1].0, podcastEpisodePairs[0].1, podcastEpisodePairs[0].2,
//            "Different Episode", Date(), 0, Date(),
//          ]
//        )
//      }
//    }
//  }
//
//  @Test("v17 migration works with Episode model after migration")
//  func testV17MigrationWithEpisodeModel() async throws {
//    // Apply full migration including v17
//    try migrator.migrate(appDB.db)
//
//    // Create test data using Episode model (which should use mediaURL column)
//    let testPodcast = try UnsavedPodcast(
//      feedURL: FeedURL(URL(string: "https://example.com/feed.xml")!),
//      title: "Test Podcast",
//      image: URL(string: "https://example.com/image.jpg")!,
//      description: "Test Description"
//    )
//
//    let testEpisode = try UnsavedEpisode(
//      guid: GUID("test-model-guid"),
//      media: MediaURL(URL(string: "https://example.com/episode.mp3")!),
//      title: "Test Model Episode",
//      pubDate: Date(),
//      duration: CMTime.seconds(1800)
//    )
//
//    // Insert using GRDB model methods
//    try await appDB.db.write { db in
//      var podcast = testPodcast
//      let insertedPodcast = try podcast.insertAndFetch(db, as: Podcast.self)
//
//      var episode = testEpisode
//      episode.podcastId = insertedPodcast.id
//      let insertedEpisode = try episode.insertAndFetch(db, as: Episode.self)
//
//      #expect(insertedEpisode.media == testEpisode.media)
//      #expect(insertedEpisode.title == testEpisode.title)
//    }
//
//    // Verify we can query using the new column
//    let fetchedEpisode = try await appDB.db.read { db in
//      try Episode.fetchOne(
//        db,
//        sql: "SELECT * FROM episode WHERE mediaURL = ?",
//        arguments: [testEpisode.media.rawValue]
//      )
//    }
//
//    #expect(fetchedEpisode != nil)
//    #expect(fetchedEpisode!.media == testEpisode.media)
//    #expect(fetchedEpisode!.title == testEpisode.title)
//  }
}
