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

  @Test("migrating to v2, assigning completion dates")
  func testV2Migration() async throws {
    try migrator.migrate(appDB.db, upTo: "v1")

    // Insert test data in v1 schema (with 'completed' column)
    let now = Date()
    let yesterday = 24.hoursAgo

    try await appDB.db.write { db in
      // Create a podcast
      try db.execute(
        sql: """
            INSERT INTO podcast (feedURL, title, image, description, subscribed)
            VALUES ('https://example.com/feed.xml', 'Test Podcast', 'https://example.com/image.jpg', 'Test Description', 1)
          """
      )

      let podcastId = db.lastInsertedRowID

      // Create two episodes - one completed, one not completed
      try db.execute(
        sql: """
            INSERT INTO episode (podcastId, guid, media, title, pubDate, completed, currentTime)
            VALUES (?, 'completedGUID', 'https://example.com/ep1.mp3', 'Completed Episode', ?, 1, 0)
          """,
        arguments: [podcastId, yesterday]
      )

      try db.execute(
        sql: """
            INSERT INTO episode (podcastId, guid, media, title, pubDate, completed, currentTime)
            VALUES (?, 'uncompletedGUID', 'https://example.com/ep2.mp3', 'Incomplete Episode', ?, 0, 0)
          """,
        arguments: [podcastId, now]
      )
    }

    // Migrate to v2
    try migrator.migrate(appDB.db, upTo: "v2")

    // Verify the migration results
    try await appDB.db.read { db in
      // Check that the completed episode has completionDate set to pubDate
      let completedRow = try Row.fetchOne(
        db,
        sql: """
            SELECT * FROM episode WHERE guid = 'completedGUID'
          """
      )!

      let completionDate = completedRow[Column("completionDate")] as Date?
      let pubDate = completedRow[Column("pubDate")] as Date
      #expect(completionDate == pubDate)

      // Check that the incomplete episode has nil completionDate
      let incompleteRow = try Row.fetchOne(
        db,
        sql: """
            SELECT * FROM episode WHERE guid = 'uncompletedGUID'
          """
      )!
      #expect(incompleteRow[Column("completionDate")] as Date? == nil)

      // Verify the completed column was removed
      let columns = try db.columns(in: "episode").map { $0.name }
      #expect(columns.contains("completed") == false)
      #expect(columns.contains("completionDate") == true)
    }
  }

  @Test("migrating to v3, marking episodes complete at 95% progress")
  func testV3Migration() async throws {
    try migrator.migrate(appDB.db, upTo: "v2")

    // Insert test data in v2 schema
    let now = Date()

    try await appDB.db.write { db in
      // Create a podcast
      try db.execute(
        sql: """
            INSERT INTO podcast (feedURL, title, image, description, subscribed)
            VALUES ('https://example.com/feed.xml', 'Test Podcast', 'https://example.com/image.jpg', 'Test Description', 1)
          """
      )

      let podcastId = db.lastInsertedRowID

      // Create episodes with different progress states
      // Episode 1: 96% complete (should be marked complete)
      try db.execute(
        sql: """
            INSERT INTO episode (podcastId, guid, media, title, pubDate, duration, currentTime)
            VALUES (?, 'almost-complete', 'https://example.com/ep1.mp3', 'Almost Complete Episode', ?, 1000, 960)
          """,
        arguments: [podcastId, now]
      )

      // Episode 2: 94% complete (should NOT be marked complete)
      try db.execute(
        sql: """
            INSERT INTO episode (podcastId, guid, media, title, pubDate, duration, currentTime)
            VALUES (?, 'not-quite-complete', 'https://example.com/ep2.mp3', 'Not Quite Complete Episode', ?, 1000, 940)
          """,
        arguments: [podcastId, now]
      )

      // Episode 3: 100% complete (should be marked complete)
      try db.execute(
        sql: """
            INSERT INTO episode (podcastId, guid, media, title, pubDate, duration, currentTime)
            VALUES (?, 'fully-complete', 'https://example.com/ep3.mp3', 'Fully Complete Episode', ?, 1000, 1000)
          """,
        arguments: [podcastId, now]
      )

      // Episode 4: Already marked complete (should be unchanged)
      try db.execute(
        sql: """
            INSERT INTO episode (podcastId, guid, media, title, pubDate, duration, currentTime, completionDate)
            VALUES (?, 'already-complete', 'https://example.com/ep4.mp3', 'Already Complete Episode', ?, 1000, 800, ?)
          """,
        arguments: [podcastId, now, now]
      )

      // Episode 5: No duration (should be ignored)
      try db.execute(
        sql: """
            INSERT INTO episode (podcastId, guid, media, title, pubDate, duration, currentTime)
            VALUES (?, 'no-duration', 'https://example.com/ep5.mp3', 'No Duration Episode', ?, 0, 100)
          """,
        arguments: [podcastId, now]
      )
    }

    // Migrate to v3
    try migrator.migrate(appDB.db, upTo: "v3")

    // Verify the migration results
    try await appDB.db.read { db in
      // Episode 1: Should be marked complete with currentTime reset to 0
      let ep1 = try Row.fetchOne(db, sql: "SELECT * FROM episode WHERE guid = 'almost-complete'")!
      #expect(ep1[Column("completionDate")] as Date? != nil)
      #expect(ep1[Column("currentTime")] as Double == 0)

      // Episode 2: Should remain incomplete
      let ep2 = try Row.fetchOne(
        db,
        sql: "SELECT * FROM episode WHERE guid = 'not-quite-complete'"
      )!
      #expect(ep2[Column("completionDate")] as Date? == nil)
      #expect(ep2[Column("currentTime")] as Double == 940)

      // Episode 3: Should be marked complete with currentTime reset to 0
      let ep3 = try Row.fetchOne(db, sql: "SELECT * FROM episode WHERE guid = 'fully-complete'")!
      #expect(ep3[Column("completionDate")] as Date? != nil)
      #expect(ep3[Column("currentTime")] as Double == 0)

      // Episode 4: Should remain unchanged (already complete)
      let ep4 = try Row.fetchOne(db, sql: "SELECT * FROM episode WHERE guid = 'already-complete'")!
      #expect(ep4[Column("completionDate")] as Date? != nil)
      #expect(ep4[Column("currentTime")] as Double == 800)  // Should not change

      // Episode 5: Should remain unchanged (no duration)
      let ep5 = try Row.fetchOne(db, sql: "SELECT * FROM episode WHERE guid = 'no-duration'")!
      #expect(ep5[Column("completionDate")] as Date? == nil)
      #expect(ep5[Column("currentTime")] as Double == 100)
    }
  }

  @Test("migrating to v4, adding GUID update prevention trigger")
  func testV4Migration() async throws {
    try migrator.migrate(appDB.db, upTo: "v3")

    // Insert test data in v3 schema
    let now = Date()

    try await appDB.db.write { db in
      // Create a podcast
      try db.execute(
        sql: """
            INSERT INTO podcast (feedURL, title, image, description, subscribed)
            VALUES ('https://example.com/feed.xml', 'Test Podcast', 'https://example.com/image.jpg', 'Test Description', 1)
          """
      )

      let podcastId = db.lastInsertedRowID

      // Create an episode
      try db.execute(
        sql: """
            INSERT INTO episode (podcastId, guid, media, title, pubDate)
            VALUES (?, 'original-guid', 'https://example.com/ep1.mp3', 'Test Episode', ?)
          """,
        arguments: [podcastId, now]
      )
    }

    // Before migration, GUID updates should be allowed
    try await appDB.db.write { db in
      try db.execute(
        sql: "UPDATE episode SET guid = 'changed-guid' WHERE guid = 'original-guid'"
      )
    }

    // Verify the GUID was changed
    try await appDB.db.read { db in
      let count = try Int.fetchOne(
        db,
        sql: "SELECT COUNT(*) FROM episode WHERE guid = 'changed-guid'"
      )!
      #expect(count == 1)
    }

    // Migrate to v4 (adds the trigger)
    try migrator.migrate(appDB.db, upTo: "v4")

    // After migration, GUID updates should be prevented by the trigger
    await #expect(throws: DatabaseError.self) {
      try await self.appDB.db.write { db in
        try db.execute(
          sql: "UPDATE episode SET guid = 'another-guid' WHERE guid = 'changed-guid'"
        )
      }
    }

    // Verify the GUID remained unchanged
    try await appDB.db.read { db in
      let count = try Int.fetchOne(
        db,
        sql: "SELECT COUNT(*) FROM episode WHERE guid = 'changed-guid'"
      )!
      #expect(count == 1)
    }

    // Verify that other column updates still work
    try await appDB.db.write { db in
      try db.execute(
        sql: "UPDATE episode SET title = 'Updated Title' WHERE guid = 'changed-guid'"
      )
    }

    // Verify the title was updated but GUID remained the same
    try await appDB.db.read { db in
      let row = try Row.fetchOne(db, sql: "SELECT * FROM episode WHERE guid = 'changed-guid'")!
      #expect(row[Column("title")] as String == "Updated Title")
      #expect(row[Column("guid")] as String == "changed-guid")
    }
  }

  @Test("migrating to v5, fixing duplicate queueOrder values")
  func testV5Migration() async throws {
    try migrator.migrate(appDB.db, upTo: "v4")

    // Insert test data in v4 schema with duplicate queueOrder values
    let now = Date()
    let yesterday = 24.hoursAgo
    let twoDaysAgo = 48.hoursAgo
    let threeDaysAgo = 72.hoursAgo

    try await appDB.db.write { db in
      // Create a podcast
      try db.execute(
        sql: """
            INSERT INTO podcast (feedURL, title, image, description, subscribed)
            VALUES ('https://example.com/feed.xml', 'Test Podcast', 'https://example.com/image.jpg', 'Test Description', 1)
          """
      )

      let podcastId = db.lastInsertedRowID

      // Create episodes with duplicate queueOrder values (simulating the bug)
      // Episode 1: queueOrder 0, published 3 days ago (oldest)
      try db.execute(
        sql: """
            INSERT INTO episode (podcastId, guid, media, title, pubDate, queueOrder)
            VALUES (?, 'episode-1', 'https://example.com/ep1.mp3', 'Episode 1', ?, 0)
          """,
        arguments: [podcastId, threeDaysAgo]
      )

      // Episode 2: queueOrder 0, published 2 days ago (duplicate!)
      try db.execute(
        sql: """
            INSERT INTO episode (podcastId, guid, media, title, pubDate, queueOrder)
            VALUES (?, 'episode-2', 'https://example.com/ep2.mp3', 'Episode 2', ?, 0)
          """,
        arguments: [podcastId, twoDaysAgo]
      )

      // Episode 3: queueOrder 1, published yesterday (unique)
      try db.execute(
        sql: """
            INSERT INTO episode (podcastId, guid, media, title, pubDate, queueOrder)
            VALUES (?, 'episode-3', 'https://example.com/ep3.mp3', 'Episode 3', ?, 1)
          """,
        arguments: [podcastId, yesterday]
      )

      // Episode 4: queueOrder 1, published now (duplicate!)
      try db.execute(
        sql: """
            INSERT INTO episode (podcastId, guid, media, title, pubDate, queueOrder)
            VALUES (?, 'episode-4', 'https://example.com/ep4.mp3', 'Episode 4', ?, 1)
          """,
        arguments: [podcastId, now]
      )

      // Episode 5: queueOrder NULL (not in queue, should be unchanged)
      try db.execute(
        sql: """
            INSERT INTO episode (podcastId, guid, media, title, pubDate, queueOrder)
            VALUES (?, 'episode-5', 'https://example.com/ep5.mp3', 'Episode 5', ?, NULL)
          """,
        arguments: [podcastId, now]
      )
    }

    // Verify we have duplicates before migration
    try await appDB.db.read { db in
      let duplicateCount = try Int.fetchOne(
        db,
        sql: """
            SELECT COUNT(*) FROM episode 
            WHERE queueOrder IN (
              SELECT queueOrder FROM episode 
              WHERE queueOrder IS NOT NULL 
              GROUP BY queueOrder 
              HAVING COUNT(*) > 1
            )
          """
      )!
      #expect(duplicateCount > 0, "Should have duplicate queueOrder values before migration")
    }

    // Migrate to v5
    try migrator.migrate(appDB.db, upTo: "v5")

    // Verify the migration results
    try await appDB.db.read { db in
      // Check that all queueOrder values are now unique
      let totalQueued = try Int.fetchOne(
        db,
        sql: "SELECT COUNT(*) FROM episode WHERE queueOrder IS NOT NULL"
      )!
      let uniqueQueued = try Int.fetchOne(
        db,
        sql: "SELECT COUNT(DISTINCT queueOrder) FROM episode WHERE queueOrder IS NOT NULL"
      )!
      #expect(totalQueued == uniqueQueued, "All queueOrder values should be unique after migration")

      // Verify specific episode assignments (older episodes should get higher queueOrder)
      let episodes = try Row.fetchAll(
        db,
        sql: """
            SELECT guid, queueOrder, pubDate 
            FROM episode 
            WHERE queueOrder IS NOT NULL 
            ORDER BY queueOrder ASC
          """
      )

      // Episode 1 (oldest, 3 days ago) should have queueOrder 0
      #expect(episodes[0][Column("guid")] as String == "episode-1")
      #expect(episodes[0][Column("queueOrder")] as Int == 0)

      // Episode 2 (2 days ago) should have queueOrder 1
      #expect(episodes[1][Column("guid")] as String == "episode-2")
      #expect(episodes[1][Column("queueOrder")] as Int == 1)

      // Episode 3 (yesterday) should have queueOrder 2
      #expect(episodes[2][Column("guid")] as String == "episode-3")
      #expect(episodes[2][Column("queueOrder")] as Int == 2)

      // Episode 4 (now) should have queueOrder 3
      #expect(episodes[3][Column("guid")] as String == "episode-4")
      #expect(episodes[3][Column("queueOrder")] as Int == 3)

      // Episode 5 should remain NULL (not in queue)
      let ep5 = try Row.fetchOne(db, sql: "SELECT * FROM episode WHERE guid = 'episode-5'")!
      #expect(ep5[Column("queueOrder")] as Int? == nil)

      // Verify no gaps in queueOrder sequence (should be 0, 1, 2, 3)
      let queueOrders = episodes.map { $0[Column("queueOrder")] as Int }
      #expect(queueOrders == [0, 1, 2, 3])
    }
  }

  @Test("migrating to v6, changing media constraint from globally unique to unique per podcast")
  func testV6Migration() async throws {
    try migrator.migrate(appDB.db, upTo: "v5")

    // Insert test data in v5 schema
    let now = Date()

    try await appDB.db.write { db in
      // Create two podcasts
      try db.execute(
        sql: """
            INSERT INTO podcast (feedURL, title, image, description, subscribed)
            VALUES ('https://example1.com/feed.xml', 'Test Podcast 1', 'https://example1.com/image.jpg', 'Test Description 1', 1)
          """
      )
      let podcast1Id = db.lastInsertedRowID

      try db.execute(
        sql: """
            INSERT INTO podcast (feedURL, title, image, description, subscribed)
            VALUES ('https://example2.com/feed.xml', 'Test Podcast 2', 'https://example2.com/image.jpg', 'Test Description 2', 1)
          """
      )
      let podcast2Id = db.lastInsertedRowID

      // Create episodes with same media URL but different podcasts (should fail before migration)
      try db.execute(
        sql: """
            INSERT INTO episode (podcastId, guid, media, title, pubDate)
            VALUES (?, 'episode-1', 'https://example.com/shared.mp3', 'Episode 1', ?)
          """,
        arguments: [podcast1Id, now]
      )

      // This should fail due to the global unique constraint on media
      #expect(throws: DatabaseError.self) {
        try db.execute(
          sql: """
              INSERT INTO episode (podcastId, guid, media, title, pubDate)
              VALUES (?, 'episode-2', 'https://example.com/shared.mp3', 'Episode 2', ?)
            """,
          arguments: [podcast2Id, now]
        )
      }
    }

    // Migrate to v6
    try migrator.migrate(appDB.db, upTo: "v6")

    // Verify the migration results
    try await appDB.db.write { db in
      // After migration, episodes with same media URL should be allowed in different podcasts
      let podcast1Id = try Int64.fetchOne(
        db,
        sql: "SELECT id FROM podcast WHERE feedURL = 'https://example1.com/feed.xml'"
      )!
      let podcast2Id = try Int64.fetchOne(
        db,
        sql: "SELECT id FROM podcast WHERE feedURL = 'https://example2.com/feed.xml'"
      )!

      // This should now succeed
      try db.execute(
        sql: """
            INSERT INTO episode (podcastId, guid, media, title, pubDate)
            VALUES (?, 'episode-2', 'https://example.com/shared.mp3', 'Episode 2', ?)
          """,
        arguments: [podcast2Id, now]
      )

      // But duplicate media within the same podcast should still fail
      #expect(throws: DatabaseError.self) {
        try db.execute(
          sql: """
              INSERT INTO episode (podcastId, guid, media, title, pubDate)
              VALUES (?, 'episode-3', 'https://example.com/shared.mp3', 'Episode 3', ?)
            """,
          arguments: [podcast1Id, now]
        )
      }
    }

    // Verify that data was preserved during migration
    try await appDB.db.read { db in
      let episodeCount = try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM episode")!
      #expect(episodeCount == 2)

      // Verify the original episode is still there
      let originalEpisode = try Row.fetchOne(
        db,
        sql: "SELECT * FROM episode WHERE guid = 'episode-1'"
      )!
      #expect(originalEpisode[Column("media")] as String == "https://example.com/shared.mp3")
      #expect(originalEpisode[Column("title")] as String == "Episode 1")

      // Verify the new episode was inserted
      let newEpisode = try Row.fetchOne(
        db,
        sql: "SELECT * FROM episode WHERE guid = 'episode-2'"
      )!
      #expect(newEpisode[Column("media")] as String == "https://example.com/shared.mp3")
      #expect(newEpisode[Column("title")] as String == "Episode 2")
    }

    // Verify that the GUID update trigger still works after migration
    await #expect(throws: DatabaseError.self) {
      try await self.appDB.db.write { db in
        try db.execute(
          sql: "UPDATE episode SET guid = 'changed-guid' WHERE guid = 'episode-1'"
        )
      }
    }
  }

  @Test("migrating to v7, removing GUID update prevention trigger")
  func testV7Migration() async throws {
    try migrator.migrate(appDB.db, upTo: "v6")

    // Insert test data in v6 schema
    let now = Date()

    try await appDB.db.write { db in
      // Create a podcast
      try db.execute(
        sql: """
            INSERT INTO podcast (feedURL, title, image, description, subscribed)
            VALUES ('https://example.com/feed.xml', 'Test Podcast', 'https://example.com/image.jpg', 'Test Description', 1)
          """
      )

      let podcastId = db.lastInsertedRowID

      // Create an episode
      try db.execute(
        sql: """
            INSERT INTO episode (podcastId, guid, media, title, pubDate)
            VALUES (?, 'original-guid', 'https://example.com/ep1.mp3', 'Test Episode', ?)
          """,
        arguments: [podcastId, now]
      )
    }

    // Before migration v7, GUID updates should be prevented by the trigger
    await #expect(throws: DatabaseError.self) {
      try await self.appDB.db.write { db in
        try db.execute(
          sql: "UPDATE episode SET guid = 'changed-guid' WHERE guid = 'original-guid'"
        )
      }
    }

    // Verify the GUID remained unchanged
    try await appDB.db.read { db in
      let count = try Int.fetchOne(
        db,
        sql: "SELECT COUNT(*) FROM episode WHERE guid = 'original-guid'"
      )!
      #expect(count == 1)
    }

    // Migrate to v7 (removes the trigger)
    try migrator.migrate(appDB.db, upTo: "v7")

    // After migration v7, GUID updates should now be allowed
    try await appDB.db.write { db in
      try db.execute(
        sql: "UPDATE episode SET guid = 'changed-guid' WHERE guid = 'original-guid'"
      )
    }

    // Verify the GUID was successfully changed
    try await appDB.db.read { db in
      let originalCount = try Int.fetchOne(
        db,
        sql: "SELECT COUNT(*) FROM episode WHERE guid = 'original-guid'"
      )!
      #expect(originalCount == 0)

      let changedCount = try Int.fetchOne(
        db,
        sql: "SELECT COUNT(*) FROM episode WHERE guid = 'changed-guid'"
      )!
      #expect(changedCount == 1)
    }

    // Verify that other columns can still be updated
    try await appDB.db.write { db in
      try db.execute(
        sql: "UPDATE episode SET title = 'Updated Title' WHERE guid = 'changed-guid'"
      )
    }

    // Verify the title was updated
    try await appDB.db.read { db in
      let row = try Row.fetchOne(db, sql: "SELECT * FROM episode WHERE guid = 'changed-guid'")!
      #expect(row[Column("title")] as String == "Updated Title")
    }

    // Verify that updating GUID multiple times now works
    try await appDB.db.write { db in
      try db.execute(
        sql: "UPDATE episode SET guid = 'final-guid' WHERE guid = 'changed-guid'"
      )
    }

    // Verify the final GUID change
    try await appDB.db.read { db in
      let finalCount = try Int.fetchOne(
        db,
        sql: "SELECT COUNT(*) FROM episode WHERE guid = 'final-guid'"
      )!
      #expect(finalCount == 1)
    }
  }

  @Test("migrating to v8, adding lastQueued column and populating from existing queue")
  func testV8Migration() async throws {
    try migrator.migrate(appDB.db, upTo: "v7")

    // Insert test data in v7 schema
    let now = Date()
    let yesterday = 24.hoursAgo
    let twoDaysAgo = 48.hoursAgo

    let (_, episode1Id, episode2Id, episode3Id) = try await appDB.db.write { db in
      // Create a podcast
      try db.execute(
        sql: """
            INSERT INTO podcast (feedURL, title, image, description, subscribed)
            VALUES ('https://example.com/feed.xml', 'Test Podcast', 'https://example.com/image.jpg', 'Test Description', 1)
          """
      )
      let podcast1Id = db.lastInsertedRowID

      // Create episodes with some in queue and some not
      // Episode 1: In queue at position 0
      try db.execute(
        sql: """
            INSERT INTO episode (podcastId, guid, media, title, pubDate, queueOrder)
            VALUES (?, 'episode-1', 'https://example.com/ep1.mp3', 'Episode 1', ?, 0)
          """,
        arguments: [podcast1Id, twoDaysAgo]
      )
      let episode1Id = db.lastInsertedRowID

      // Episode 2: In queue at position 1
      try db.execute(
        sql: """
            INSERT INTO episode (podcastId, guid, media, title, pubDate, queueOrder)
            VALUES (?, 'episode-2', 'https://example.com/ep2.mp3', 'Episode 2', ?, 1)
          """,
        arguments: [podcast1Id, yesterday]
      )
      let episode2Id = db.lastInsertedRowID

      // Episode 3: Not in queue (queueOrder NULL)
      try db.execute(
        sql: """
            INSERT INTO episode (podcastId, guid, media, title, pubDate, queueOrder)
            VALUES (?, 'episode-3', 'https://example.com/ep3.mp3', 'Episode 3', ?, NULL)
          """,
        arguments: [podcast1Id, now]
      )
      let episode3Id = db.lastInsertedRowID

      return (podcast1Id, episode1Id, episode2Id, episode3Id)
    }

    // Verify that lastQueued column does not exist before migration
    try await appDB.db.read { db in
      let tableInfo = try Row.fetchAll(
        db,
        sql: "PRAGMA table_info(episode)"
      )
      let columnNames = tableInfo.map { $0[Column("name")] as String }
      #expect(!columnNames.contains("lastQueued"))
    }

    // Capture migration time
    let migrationTime = Date()

    // Migrate to v8
    try migrator.migrate(appDB.db, upTo: "v8")

    // Verify the lastQueued column was added to episode table
    try await appDB.db.read { db in
      let tableInfo = try Row.fetchAll(
        db,
        sql: "PRAGMA table_info(episode)"
      )
      let columnNames = tableInfo.map { $0[Column("name")] as String }
      #expect(columnNames.contains("lastQueued"))
    }

    // Verify that currently queued episodes have lastQueued set
    try await appDB.db.read { db in
      // Episode 1 should have lastQueued set
      let episode1 = try Row.fetchOne(
        db,
        sql: "SELECT * FROM episode WHERE id = ?",
        arguments: [episode1Id]
      )!
      let episode1LastQueued = episode1[Column("lastQueued")] as Date?
      #expect(episode1LastQueued != nil)

      // Verify lastQueued is essentially the migration time
      if let episode1LastQueued = episode1LastQueued {
        #expect(
          episode1LastQueued.approximatelyEquals(migrationTime),
          "Episode 1 lastQueued should be close to migration time"
        )
      }

      // Episode 2 should have lastQueued set
      let episode2 = try Row.fetchOne(
        db,
        sql: "SELECT * FROM episode WHERE id = ?",
        arguments: [episode2Id]
      )!
      let episode2LastQueued = episode2[Column("lastQueued")] as Date?
      #expect(episode2LastQueued != nil)

      // Verify lastQueued is essentially the migration time
      if let episode2LastQueued = episode2LastQueued {
        #expect(
          episode2LastQueued.approximatelyEquals(migrationTime),
          "Episode 2 lastQueued should be close to migration time"
        )
      }

      // Episode 3 (not queued) should have lastQueued as NULL
      let episode3 = try Row.fetchOne(
        db,
        sql: "SELECT * FROM episode WHERE id = ?",
        arguments: [episode3Id]
      )!
      let episode3LastQueued = episode3[Column("lastQueued")] as Date?
      #expect(episode3LastQueued == nil)
    }
  }

  @Test("migrating to v9, converting subscribed boolean to subscriptionDate")
  func testV9Migration() async throws {
    try migrator.migrate(appDB.db, upTo: "v8")

    let (
      subscribedPodcast1Id, subscribedPodcast2Id, unsubscribedPodcast1Id, unsubscribedPodcast2Id
    ) = try await appDB.db.write { db in
      // Create subscribed podcasts
      try db.execute(
        sql: """
            INSERT INTO podcast (feedURL, title, image, description, subscribed)
            VALUES ('https://example1.com/feed.xml', 'Subscribed Podcast 1', 'https://example1.com/image.jpg', 'Test Description 1', 1)
          """
      )
      let subscribedPodcast1Id = db.lastInsertedRowID

      try db.execute(
        sql: """
            INSERT INTO podcast (feedURL, title, image, description, subscribed)
            VALUES ('https://example2.com/feed.xml', 'Subscribed Podcast 2', 'https://example2.com/image.jpg', 'Test Description 2', 1)
          """
      )
      let subscribedPodcast2Id = db.lastInsertedRowID

      // Create unsubscribed podcasts
      try db.execute(
        sql: """
            INSERT INTO podcast (feedURL, title, image, description, subscribed)
            VALUES ('https://example3.com/feed.xml', 'Unsubscribed Podcast 1', 'https://example3.com/image.jpg', 'Test Description 3', 0)
          """
      )
      let unsubscribedPodcast1Id = db.lastInsertedRowID

      try db.execute(
        sql: """
            INSERT INTO podcast (feedURL, title, image, description, subscribed)
            VALUES ('https://example4.com/feed.xml', 'Unsubscribed Podcast 2', 'https://example4.com/image.jpg', 'Test Description 4', 0)
          """
      )
      let unsubscribedPodcast2Id = db.lastInsertedRowID

      return (
        subscribedPodcast1Id, subscribedPodcast2Id, unsubscribedPodcast1Id, unsubscribedPodcast2Id
      )
    }

    // Verify that subscribed column exists and subscriptionDate does not exist before migration
    try await appDB.db.read { db in
      let tableInfo = try Row.fetchAll(db, sql: "PRAGMA table_info(podcast)")
      let columnNames = tableInfo.map { $0[Column("name")] as String }
      #expect(columnNames.contains("subscribed"))
      #expect(!columnNames.contains("subscriptionDate"))

      // Verify initial subscription state
      let subscribedCount = try Int.fetchOne(
        db,
        sql: "SELECT COUNT(*) FROM podcast WHERE subscribed = 1"
      )!
      let unsubscribedCount = try Int.fetchOne(
        db,
        sql: "SELECT COUNT(*) FROM podcast WHERE subscribed = 0"
      )!
      #expect(subscribedCount == 2)
      #expect(unsubscribedCount == 2)
    }

    // Capture migration time
    let migrationTime = Date()

    // Migrate to v9
    try migrator.migrate(appDB.db, upTo: "v9")

    // Verify the migration results
    try await appDB.db.read { db in
      // Verify column changes
      let tableInfo = try Row.fetchAll(db, sql: "PRAGMA table_info(podcast)")
      let columnNames = tableInfo.map { $0[Column("name")] as String }
      #expect(!columnNames.contains("subscribed"), "Old subscribed column should be removed")
      #expect(
        columnNames.contains("subscriptionDate"),
        "New subscriptionDate column should be added"
      )

      // Verify subscribed podcasts now have subscriptionDate set
      let subscribedPodcast1 = try Row.fetchOne(
        db,
        sql: "SELECT * FROM podcast WHERE id = ?",
        arguments: [subscribedPodcast1Id]
      )!
      let subscribedPodcast1Date = subscribedPodcast1[Column("subscriptionDate")] as Date?
      #expect(
        subscribedPodcast1Date != nil,
        "Subscribed podcast 1 should have subscriptionDate set"
      )

      if let subscriptionDate = subscribedPodcast1Date {
        #expect(
          subscriptionDate.approximatelyEquals(migrationTime),
          "Subscription date should be close to migration time"
        )
      }

      let subscribedPodcast2 = try Row.fetchOne(
        db,
        sql: "SELECT * FROM podcast WHERE id = ?",
        arguments: [subscribedPodcast2Id]
      )!
      let subscribedPodcast2Date = subscribedPodcast2[Column("subscriptionDate")] as Date?
      #expect(
        subscribedPodcast2Date != nil,
        "Subscribed podcast 2 should have subscriptionDate set"
      )

      // Verify unsubscribed podcasts have subscriptionDate as NULL
      let unsubscribedPodcast1 = try Row.fetchOne(
        db,
        sql: "SELECT * FROM podcast WHERE id = ?",
        arguments: [unsubscribedPodcast1Id]
      )!
      let unsubscribedPodcast1Date = unsubscribedPodcast1[Column("subscriptionDate")] as Date?
      #expect(
        unsubscribedPodcast1Date == nil,
        "Unsubscribed podcast 1 should have subscriptionDate as NULL"
      )

      let unsubscribedPodcast2 = try Row.fetchOne(
        db,
        sql: "SELECT * FROM podcast WHERE id = ?",
        arguments: [unsubscribedPodcast2Id]
      )!
      let unsubscribedPodcast2Date = unsubscribedPodcast2[Column("subscriptionDate")] as Date?
      #expect(
        unsubscribedPodcast2Date == nil,
        "Unsubscribed podcast 2 should have subscriptionDate as NULL"
      )

      // Verify counts using new subscriptionDate column
      let newSubscribedCount = try Int.fetchOne(
        db,
        sql: "SELECT COUNT(*) FROM podcast WHERE subscriptionDate IS NOT NULL"
      )!
      let newUnsubscribedCount = try Int.fetchOne(
        db,
        sql: "SELECT COUNT(*) FROM podcast WHERE subscriptionDate IS NULL"
      )!
      #expect(newSubscribedCount == 2, "Should have 2 podcasts with subscriptionDate set")
      #expect(newUnsubscribedCount == 2, "Should have 2 podcasts with subscriptionDate as NULL")
    }
  }
}
