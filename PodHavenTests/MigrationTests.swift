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
}
