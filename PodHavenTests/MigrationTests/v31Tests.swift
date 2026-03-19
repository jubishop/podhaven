// Copyright Justin Bishop, 2025

import Foundation
import GRDB
import Testing

@testable import PodHaven

@Suite("v31 migration tests", .container)
class V31MigrationTests {
  private let appDB = AppDB.inMemory(migrate: false)
  private let migrator: DatabaseMigrator

  init() async throws {
    self.migrator = Schema.makeMigrator()
  }

  @Test("v31 migration adds iTunesID column to podcast table with unique constraint")
  func testV31Migration() async throws {
    // Apply migrations up to v30
    try migrator.migrate(appDB.db, upTo: "v30")

    // Insert test podcast before migration
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

    // Verify iTunesID column doesn't exist yet
    try await appDB.db.read { db in
      let cols = try Row.fetchAll(db, sql: "PRAGMA table_info('podcast')")
      let colNames = Set(cols.compactMap { $0["name"] as? String })
      #expect(
        !colNames.contains("iTunesID"),
        "iTunesID column should not exist before v31"
      )
    }

    // Apply v31 migration
    try migrator.migrate(appDB.db, upTo: "v31")

    // Verify iTunesID column exists after migration
    try await appDB.db.read { db in
      let cols = try Row.fetchAll(db, sql: "PRAGMA table_info('podcast')")
      let colNames = Set(cols.compactMap { $0["name"] as? String })
      #expect(
        colNames.contains("iTunesID"),
        "iTunesID column should exist after v31"
      )

      let iTunesIDCol = cols.first { $0["name"] as? String == "iTunesID" }
      #expect(iTunesIDCol != nil)
      let type = iTunesIDCol?["type"] as? String
      #expect(type == "INTEGER", "iTunesID should be INTEGER type")
    }

    // Verify existing podcast has NULL iTunesID after migration
    try await appDB.db.read { db in
      let row = try Row.fetchOne(
        db,
        sql: "SELECT iTunesID FROM podcast WHERE id = ?",
        arguments: [testPodcastID]
      )
      #expect(row != nil, "Podcast row should exist")
      #expect(row?["iTunesID"] == nil, "Existing podcast should have NULL iTunesID after migration")
    }

    // Insert podcasts with iTunesID values
    try await appDB.db.write { db in
      try db.execute(
        sql: """
          INSERT INTO podcast (feedURL, title, image, description, iTunesID)
          VALUES (?, ?, ?, ?, ?)
          """,
        arguments: [
          "https://example.com/feed-with-id.xml",
          "Podcast With ID",
          "https://example.com/image2.jpg",
          "Test Description 2",
          12345,
        ]
      )
    }

    // Verify uniqueness constraint — inserting duplicate iTunesID should fail
    await #expect(throws: DatabaseError.self) {
      try await self.appDB.db.write { db in
        try db.execute(
          sql: """
            INSERT INTO podcast (feedURL, title, image, description, iTunesID)
            VALUES (?, ?, ?, ?, ?)
            """,
          arguments: [
            "https://example.com/feed-dup.xml",
            "Duplicate ID Podcast",
            "https://example.com/image3.jpg",
            "Test Description 3",
            12345,
          ]
        )
      }
    }

    // Verify multiple NULL iTunesIDs are allowed (NULL != NULL in SQL)
    try await appDB.db.write { db in
      try db.execute(
        sql: """
          INSERT INTO podcast (feedURL, title, image, description)
          VALUES (?, ?, ?, ?)
          """,
        arguments: [
          "https://example.com/feed-null.xml",
          "Podcast No ID",
          "https://example.com/image4.jpg",
          "Test Description 4",
        ]
      )
    }

    let nullCount = try await appDB.db.read { db in
      try Int.fetchOne(
        db,
        sql: "SELECT COUNT(*) FROM podcast WHERE iTunesID IS NULL"
      )
    }
    #expect(nullCount == 2, "Should have 2 podcasts with NULL iTunesID")
  }
}
