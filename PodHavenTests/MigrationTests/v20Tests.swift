// Copyright Justin Bishop, 2025

import Foundation
import GRDB
import Testing

@testable import PodHaven

@Suite("v20 migration tests", .container)
class V20MigrationTests {
  private let appDB = AppDB.inMemory(migrate: false)
  private let migrator: DatabaseMigrator

  init() async throws {
    self.migrator = try Schema.makeMigrator()
  }

  @Test("v20 migration renames lastQueued to queueDate in episode table")
  func testV20Migration() async throws {
    // Apply migrations up to v19
    try migrator.migrate(appDB.db, upTo: "v19")

    // Insert test data before migration
    let testPodcastID = try await appDB.db.write { db in
      try db.execute(
        sql: """
          INSERT INTO podcast (feedURL, title, image, description)
          VALUES (?, ?, ?, ?)
          """,
        arguments: [
          "https://example.com/feed.xml",
          "Test Podcast",
          "https://example.com/image.jpg",
          "Test Description",
        ]
      )
      return db.lastInsertedRowID
    }

    let testQueueDate = Date()
    let testEpisodeID = try await appDB.db.write { db in
      try db.execute(
        sql: """
          INSERT INTO episode (
            podcastId, guid, mediaURL, title, pubDate, lastQueued
          ) VALUES (?, ?, ?, ?, ?, ?)
          """,
        arguments: [
          testPodcastID,
          "test-guid",
          "https://example.com/episode.mp3",
          "Test Episode",
          Date(),
          testQueueDate,
        ]
      )
      return db.lastInsertedRowID
    }

    // Verify lastQueued column exists before migration
    try await appDB.db.read { db in
      let cols = try Row.fetchAll(db, sql: "PRAGMA table_info('episode')")
      let colNames = Set(cols.compactMap { $0["name"] as? String })
      #expect(
        colNames.contains("lastQueued"),
        "lastQueued column should exist before v20"
      )
      #expect(
        !colNames.contains("queueDate"),
        "queueDate column should not exist before v20"
      )
    }

    // Verify data is accessible via old column name
    let preLastQueued = try await appDB.db.read { db in
      try Date.fetchOne(
        db,
        sql: "SELECT lastQueued FROM episode WHERE id = ?",
        arguments: [testEpisodeID]
      )
    }
    #expect(
      preLastQueued?.approximatelyEquals(testQueueDate) == true,
      "Should be able to read lastQueued before migration"
    )

    // Apply v20 migration
    try migrator.migrate(appDB.db, upTo: "v20")

    // Verify queueDate column exists after migration
    try await appDB.db.read { db in
      let cols = try Row.fetchAll(db, sql: "PRAGMA table_info('episode')")
      let colNames = Set(cols.compactMap { $0["name"] as? String })
      #expect(
        colNames.contains("queueDate"),
        "queueDate column should exist after v20"
      )
      #expect(
        !colNames.contains("lastQueued"),
        "lastQueued column should not exist after v20"
      )
    }

    // Verify data was preserved in renamed column
    let postQueueDate = try await appDB.db.read { db in
      try Date.fetchOne(
        db,
        sql: "SELECT queueDate FROM episode WHERE id = ?",
        arguments: [testEpisodeID]
      )
    }
    #expect(
      postQueueDate?.approximatelyEquals(testQueueDate) == true,
      "Data should be preserved after column rename"
    )

    // Verify we can't access old column name after migration
    await #expect(throws: DatabaseError.self) {
      try await self.appDB.db.read { db in
        try Date.fetchOne(
          db,
          sql: "SELECT lastQueued FROM episode WHERE id = ?",
          arguments: [testEpisodeID]
        )
      }
    }

    // Test inserting new episode with queueDate
    try await appDB.db.write { db in
      try db.execute(
        sql: """
          INSERT INTO episode (
            podcastId, guid, mediaURL, title, pubDate, queueDate
          ) VALUES (?, ?, ?, ?, ?, ?)
          """,
        arguments: [
          testPodcastID,
          "test-guid-2",
          "https://example.com/episode2.mp3",
          "Test Episode 2",
          Date(),
          Date(),
        ]
      )
    }

    // Verify new episode was inserted successfully
    let episodeCount = try await appDB.db.read { db in
      try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM episode")
    }
    #expect(episodeCount == 2, "Should have 2 episodes after inserting new one")
  }
}
