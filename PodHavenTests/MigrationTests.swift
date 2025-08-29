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

  @Test("migrating to v13, adding cacheAllEpisodes column to podcast table")
  func testV13Migration() async throws {
    try migrator.migrate(appDB.db, upTo: "v1")

    // Insert test data in v12 schema
    let now = Date()

    let (podcast1Id, podcast2Id) = try await appDB.db.write { db in
      // Create two podcasts - one subscribed, one unsubscribed
      try db.execute(
        sql: """
          INSERT INTO podcast (feedURL, title, image, description, subscriptionDate)
          VALUES ('https://example1.com/feed.xml', 'Subscribed Podcast', 'https://example1.com/image.jpg', 'Subscribed Description', ?)
          """,
        arguments: [now]
      )
      let podcast1Id = db.lastInsertedRowID

      try db.execute(
        sql: """
          INSERT INTO podcast (feedURL, title, image, description, subscriptionDate)
          VALUES ('https://example2.com/feed.xml', 'Unsubscribed Podcast', 'https://example2.com/image.jpg', 'Unsubscribed Description', NULL)
          """
      )
      let podcast2Id = db.lastInsertedRowID

      return (podcast1Id, podcast2Id)
    }

    // Verify cacheAllEpisodes column does not exist before migration
    try await appDB.db.read { db in
      let columnNames = try db.columns(in: "podcast").map(\.name)
      #expect(
        !columnNames.contains("cacheAllEpisodes"),
        "cacheAllEpisodes column should not exist before migration"
      )
    }

    // Migrate to v13
    try migrator.migrate(appDB.db, upTo: "v13")

    // Verify the migration results
    try await appDB.db.read { db in
      // Verify cacheAllEpisodes column was added
      let columnNames = try db.columns(in: "podcast").map(\.name)
      #expect(
        columnNames.contains("cacheAllEpisodes"),
        "cacheAllEpisodes column should exist after migration"
      )

      // Verify existing podcasts have default cacheAllEpisodes value of false
      let podcast1 = try Row.fetchOne(
        db,
        sql: "SELECT * FROM podcast WHERE id = ?",
        arguments: [podcast1Id]
      )!
      let podcast1CacheAll = podcast1[Column("cacheAllEpisodes")] as Bool
      #expect(
        podcast1CacheAll == false,
        "Subscribed podcast should have cacheAllEpisodes defaulting to false"
      )

      let podcast2 = try Row.fetchOne(
        db,
        sql: "SELECT * FROM podcast WHERE id = ?",
        arguments: [podcast2Id]
      )!
      let podcast2CacheAll = podcast2[Column("cacheAllEpisodes")] as Bool
      #expect(
        podcast2CacheAll == false,
        "Unsubscribed podcast should have cacheAllEpisodes defaulting to false"
      )

      // Verify all other podcast data is preserved
      #expect(podcast1[Column("feedURL")] as String == "https://example1.com/feed.xml")
      #expect(podcast1[Column("title")] as String == "Subscribed Podcast")
      #expect(podcast1[Column("description")] as String == "Subscribed Description")
      #expect(podcast1[Column("subscriptionDate")] as Date? != nil)

      #expect(podcast2[Column("feedURL")] as String == "https://example2.com/feed.xml")
      #expect(podcast2[Column("title")] as String == "Unsubscribed Podcast")
      #expect(podcast2[Column("description")] as String == "Unsubscribed Description")
      #expect(podcast2[Column("subscriptionDate")] as Date? == nil)
    }

    // Verify that cacheAllEpisodes can be updated after migration
    try await appDB.db.write { db in
      try db.execute(
        sql: "UPDATE podcast SET cacheAllEpisodes = ? WHERE id = ?",
        arguments: [true, podcast1Id]
      )
    }

    // Verify the update worked
    try await appDB.db.read { db in
      let updatedPodcast1 = try Row.fetchOne(
        db,
        sql: "SELECT * FROM podcast WHERE id = ?",
        arguments: [podcast1Id]
      )!
      let updatedCacheAll = updatedPodcast1[Column("cacheAllEpisodes")] as Bool
      #expect(
        updatedCacheAll == true,
        "Podcast cacheAllEpisodes should be updatable after migration"
      )
    }

    // Verify that new podcasts can be inserted with cacheAllEpisodes values
    try await appDB.db.write { db in
      try db.execute(
        sql: """
          INSERT INTO podcast (feedURL, title, image, description, cacheAllEpisodes)
          VALUES ('https://example3.com/feed.xml', 'New Podcast', 'https://example3.com/image.jpg', 'New Description', ?)
          """,
        arguments: [true]
      )
    }

    // Verify the new podcast was inserted with correct cacheAllEpisodes value
    try await appDB.db.read { db in
      let newPodcast = try Row.fetchOne(
        db,
        sql: "SELECT * FROM podcast WHERE feedURL = 'https://example3.com/feed.xml'"
      )!
      let newCacheAll = newPodcast[Column("cacheAllEpisodes")] as Bool
      #expect(
        newCacheAll == true,
        "New podcast should have cacheAllEpisodes set to true"
      )
    }
  }

  @Test("migrating to v14, adding creationDate columns to episode and podcast tables")
  func testV14Migration() async throws {
    try migrator.migrate(appDB.db, upTo: "v13")

    // Insert test data in v13 schema
    let now = Date()
    let yesterday = 24.hoursAgo

    let (podcast1Id, podcast2Id, episode1Id, episode2Id, episode3Id) = try await appDB.db.write {
      db in
      // Create two podcasts - one subscribed, one unsubscribed
      try db.execute(
        sql: """
          INSERT INTO podcast (feedURL, title, image, description, subscriptionDate, cacheAllEpisodes)
          VALUES ('https://example1.com/feed.xml', 'Subscribed Podcast', 'https://example1.com/image.jpg', 'Subscribed Description', ?, ?)
          """,
        arguments: [now, false]
      )
      let podcast1Id = db.lastInsertedRowID

      try db.execute(
        sql: """
          INSERT INTO podcast (feedURL, title, image, description, subscriptionDate, cacheAllEpisodes)
          VALUES ('https://example2.com/feed.xml', 'Unsubscribed Podcast', 'https://example2.com/image.jpg', 'Unsubscribed Description', NULL, ?)
          """,
        arguments: [true]
      )
      let podcast2Id = db.lastInsertedRowID

      // Create episodes for both podcasts
      try db.execute(
        sql: """
          INSERT INTO episode (podcastId, guid, media, title, pubDate, duration, currentTime, queueOrder, lastQueued, cachedFilename)
          VALUES (?, 'episode1-guid', 'https://example1.com/ep1.mp3', 'Episode 1', ?, ?, ?, ?, ?, ?)
          """,
        arguments: [podcast1Id, yesterday, 1800, 900, 0, yesterday, "ep1.mp3"]
      )
      let episode1Id = db.lastInsertedRowID

      try db.execute(
        sql: """
          INSERT INTO episode (podcastId, guid, media, title, pubDate, completionDate, currentTime, cachedFilename)
          VALUES (?, 'episode2-guid', 'https://example1.com/ep2.mp3', 'Episode 2', ?, ?, ?, ?)
          """,
        arguments: [podcast1Id, now, now, 0, "ep2.mp3"]
      )
      let episode2Id = db.lastInsertedRowID

      try db.execute(
        sql: """
          INSERT INTO episode (podcastId, guid, media, title, pubDate, duration, currentTime)
          VALUES (?, 'episode3-guid', 'https://example2.com/ep3.mp3', 'Episode 3', ?, ?, ?)
          """,
        arguments: [podcast2Id, yesterday, 2400, 120]
      )
      let episode3Id = db.lastInsertedRowID

      return (podcast1Id, podcast2Id, episode1Id, episode2Id, episode3Id)
    }

    // Verify creationDate columns do not exist before migration
    try await appDB.db.read { db in
      let podcastColumns = try db.columns(in: "podcast").map(\.name)
      #expect(
        !podcastColumns.contains("creationDate"),
        "creationDate column should not exist on podcast table before migration"
      )

      let episodeColumns = try db.columns(in: "episode").map(\.name)
      #expect(
        !episodeColumns.contains("creationDate"),
        "creationDate column should not exist on episode table before migration"
      )
    }

    // Record the time just before migration
    let migrationTime = Date()

    // Migrate to v14
    try migrator.migrate(appDB.db, upTo: "v14")

    // Verify the migration results
    try await appDB.db.read { db in
      // Verify creationDate columns were added to both tables
      let podcastColumns = try db.columns(in: "podcast").map(\.name)
      #expect(
        podcastColumns.contains("creationDate"),
        "creationDate column should exist on podcast table after migration"
      )

      let episodeColumns = try db.columns(in: "episode").map(\.name)
      #expect(
        episodeColumns.contains("creationDate"),
        "creationDate column should exist on episode table after migration"
      )

      // Verify existing podcasts have creationDate set to CURRENT_TIMESTAMP (migration time)
      let podcast1 = try Row.fetchOne(
        db,
        sql: "SELECT * FROM podcast WHERE id = ?",
        arguments: [podcast1Id]
      )!
      let podcast1CreationDate = podcast1[Column("creationDate")] as Date
      #expect(
        podcast1CreationDate.approximatelyEquals(migrationTime, accuracy: .seconds(5)),
        "Subscribed podcast should have creationDate set to migration time"
      )

      let podcast2 = try Row.fetchOne(
        db,
        sql: "SELECT * FROM podcast WHERE id = ?",
        arguments: [podcast2Id]
      )!
      let podcast2CreationDate = podcast2[Column("creationDate")] as Date
      #expect(
        podcast2CreationDate.approximatelyEquals(migrationTime, accuracy: .seconds(5)),
        "Unsubscribed podcast should have creationDate set to migration time"
      )

      // Verify existing episodes have creationDate set to CURRENT_TIMESTAMP (migration time)
      let episode1 = try Row.fetchOne(
        db,
        sql: "SELECT * FROM episode WHERE id = ?",
        arguments: [episode1Id]
      )!
      let episode1CreationDate = episode1[Column("creationDate")] as Date
      #expect(
        episode1CreationDate.approximatelyEquals(migrationTime, accuracy: .seconds(5)),
        "Episode 1 should have creationDate set to migration time"
      )

      let episode2 = try Row.fetchOne(
        db,
        sql: "SELECT * FROM episode WHERE id = ?",
        arguments: [episode2Id]
      )!
      let episode2CreationDate = episode2[Column("creationDate")] as Date
      #expect(
        episode2CreationDate.approximatelyEquals(migrationTime, accuracy: .seconds(5)),
        "Episode 2 should have creationDate set to migration time"
      )

      let episode3 = try Row.fetchOne(
        db,
        sql: "SELECT * FROM episode WHERE id = ?",
        arguments: [episode3Id]
      )!
      let episode3CreationDate = episode3[Column("creationDate")] as Date
      #expect(
        episode3CreationDate.approximatelyEquals(migrationTime, accuracy: .seconds(5)),
        "Episode 3 should have creationDate set to migration time"
      )

      // Verify all other podcast data is preserved
      #expect(podcast1[Column("feedURL")] as String == "https://example1.com/feed.xml")
      #expect(podcast1[Column("title")] as String == "Subscribed Podcast")
      #expect(podcast1[Column("description")] as String == "Subscribed Description")
      #expect(podcast1[Column("subscriptionDate")] as Date? != nil)
      #expect(podcast1[Column("cacheAllEpisodes")] as Bool == false)

      #expect(podcast2[Column("feedURL")] as String == "https://example2.com/feed.xml")
      #expect(podcast2[Column("title")] as String == "Unsubscribed Podcast")
      #expect(podcast2[Column("description")] as String == "Unsubscribed Description")
      #expect(podcast2[Column("subscriptionDate")] as Date? == nil)
      #expect(podcast2[Column("cacheAllEpisodes")] as Bool == true)

      // Verify all other episode data is preserved
      #expect(episode1[Column("guid")] as String == "episode1-guid")
      #expect(episode1[Column("title")] as String == "Episode 1")
      #expect(episode1[Column("duration")] as Double == 1800)
      #expect(episode1[Column("currentTime")] as Double == 900)
      #expect(episode1[Column("queueOrder")] as Int? == 0)
      #expect(episode1[Column("cachedFilename")] as String? == "ep1.mp3")

      #expect(episode2[Column("guid")] as String == "episode2-guid")
      #expect(episode2[Column("title")] as String == "Episode 2")
      #expect(episode2[Column("completionDate")] as Date? != nil)
      #expect(episode2[Column("currentTime")] as Double == 0)
      #expect(episode2[Column("cachedFilename")] as String? == "ep2.mp3")

      #expect(episode3[Column("guid")] as String == "episode3-guid")
      #expect(episode3[Column("title")] as String == "Episode 3")
      #expect(episode3[Column("duration")] as Double == 2400)
      #expect(episode3[Column("currentTime")] as Double == 120)
    }

    // Verify that new records get CURRENT_TIMESTAMP
    let insertTime = Date()
    try await appDB.db.write { db in
      try db.execute(
        sql: """
          INSERT INTO podcast (feedURL, title, image, description, cacheAllEpisodes)
          VALUES ('https://example4.com/feed.xml', 'Auto Date Podcast', 'https://example4.com/image.jpg', 'Auto Description', ?)
          """,
        arguments: [true]
      )
      let autoPodcastId = db.lastInsertedRowID

      try db.execute(
        sql: """
          INSERT INTO episode (podcastId, guid, media, title, pubDate, duration, currentTime)
          VALUES (?, 'auto-episode-guid', 'https://example4.com/auto-ep.mp3', 'Auto Episode', ?, ?, ?)
          """,
        arguments: [autoPodcastId, now, 1200, 0]
      )
    }

    // Verify automatic timestamp assignment
    try await appDB.db.read { db in
      let autoPodcast = try Row.fetchOne(
        db,
        sql: "SELECT * FROM podcast WHERE feedURL = 'https://example4.com/feed.xml'"
      )!
      let autoPodcastCreationDate = autoPodcast[Column("creationDate")] as Date
      #expect(
        autoPodcastCreationDate.approximatelyEquals(insertTime, accuracy: .seconds(5)),
        "Auto-created podcast should have creationDate set to current timestamp"
      )

      let autoEpisode = try Row.fetchOne(
        db,
        sql: "SELECT * FROM episode WHERE guid = 'auto-episode-guid'"
      )!
      let autoEpisodeCreationDate = autoEpisode[Column("creationDate")] as Date
      #expect(
        autoEpisodeCreationDate.approximatelyEquals(insertTime, accuracy: .seconds(5)),
        "Auto-created episode should have creationDate set to current timestamp"
      )
    }

    // Verify final index names after migration
    try await appDB.db.read { db in
      // Get all indexes in the database
      let indexes = try Row.fetchAll(
        db,
        sql: "SELECT name, tbl_name FROM sqlite_master WHERE type = 'index' AND name NOT LIKE 'sqlite_%' ORDER BY name"
      )
      
      let expectedIndexes = [
        "episode_on_guid": "episode",
        "episode_on_media": "episode",
        "episode_on_podcastId": "episode",
        "podcast_on_feedURL": "podcast"
      ]
      
      // Check that we have exactly the expected indexes
      #expect(indexes.count == expectedIndexes.count, "Should have exactly \(expectedIndexes.count) indexes")
      
      for index in indexes {
        let indexName = index["name"] as! String
        let tableName = index["tbl_name"] as! String
        
        #expect(expectedIndexes[indexName] != nil, "Unexpected index: \(indexName)")
        #expect(expectedIndexes[indexName] == tableName, "Index \(indexName) should be on table \(expectedIndexes[indexName]!) but is on \(tableName)")
      }
    }
  }

  @Test("migrating to v15, adding unique constraint on guid+media combination")
  func testV15Migration() async throws {
    try migrator.migrate(appDB.db, upTo: "v14")

    // Insert test data in v14 schema with some duplicate guid+media combinations
    let now = Date()
    let yesterday = 24.hoursAgo

    let (podcast1Id, podcast2Id, episode1Id, episode2Id, episode3Id, episode4Id) = try await appDB.db.write { db in
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
      let duplicateCount = try Int.fetchOne(db, sql: """
        SELECT COUNT(*) FROM (
          SELECT guid, media, COUNT(*) as count
          FROM episode 
          GROUP BY guid, media 
          HAVING COUNT(*) > 1
        )
        """)!
      #expect(duplicateCount == 1, "Should have 1 duplicate guid+media combination before migration")
    }

    // Verify unique constraint doesn't exist before migration
    try await appDB.db.read { db in
      let indexes = try Row.fetchAll(
        db,
        sql: "SELECT name FROM sqlite_master WHERE type = 'index' AND name = 'episode_on_guid_media'"
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
        sql: "SELECT name FROM sqlite_master WHERE type = 'index' AND name = 'episode_on_guid_media'"
      )
      #expect(indexes.count == 1, "episode_on_guid_media unique index should exist after migration")

      // Verify duplicates were removed - should now have 3 episodes instead of 5
      let episodeCount = try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM episode")!
      #expect(episodeCount == 3, "Should have 3 episodes after removing duplicates")

      // Verify no duplicate guid+media combinations remain
      let duplicateCount = try Int.fetchOne(db, sql: """
        SELECT COUNT(*) FROM (
          SELECT guid, media, COUNT(*) as count
          FROM episode 
          GROUP BY guid, media 
          HAVING COUNT(*) > 1
        )
        """)!
      #expect(duplicateCount == 0, "Should have no duplicate guid+media combinations after migration")

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
      #expect(episode2["title"] as! String == "Original Episode", "Episode 2 should be the original")

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
      #expect(episodeCount == 6, "Should have 6 episodes after inserting episodes with partial matches")

      // Verify we still have no duplicate guid+media combinations
      let duplicateCount = try Int.fetchOne(db, sql: """
        SELECT COUNT(*) FROM (
          SELECT guid, media, COUNT(*) as count
          FROM episode 
          GROUP BY guid, media 
          HAVING COUNT(*) > 1
        )
        """)!
      #expect(duplicateCount == 0, "Should still have no duplicate guid+media combinations")
    }
  }
}
