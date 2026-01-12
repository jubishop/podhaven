// Copyright Justin Bishop, 2025

import Foundation
import GRDB
import Testing

@testable import PodHaven

@Suite("v18 migration tests", .container)
class V18MigrationTests {
  private let appDB = AppDB.inMemory(migrate: false)
  private let migrator: DatabaseMigrator

  init() async throws {
    self.migrator = try Schema.makeMigrator()
  }

  @Test("v18 migration adds defaultPlaybackRate column to podcast table with check constraint")
  func testV18Migration() async throws {
    // Apply migrations up to v1
    try migrator.migrate(appDB.db, upTo: "v1")

    // Insert a test podcast before migration
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

    // Verify defaultPlaybackRate column doesn't exist yet
    try await appDB.db.read { db in
      let cols = try Row.fetchAll(db, sql: "PRAGMA table_info('podcast')")
      let colNames = Set(cols.compactMap { $0["name"] as? String })
      #expect(
        !colNames.contains("defaultPlaybackRate"),
        "defaultPlaybackRate column should not exist before v18"
      )
    }

    // Apply v18 migration
    try migrator.migrate(appDB.db, upTo: "v18")

    // Verify defaultPlaybackRate column exists after migration
    try await appDB.db.read { db in
      let cols = try Row.fetchAll(db, sql: "PRAGMA table_info('podcast')")
      let colNames = Set(cols.compactMap { $0["name"] as? String })
      #expect(
        colNames.contains("defaultPlaybackRate"),
        "defaultPlaybackRate column should exist after v18"
      )

      // Verify it's a DOUBLE type
      let defaultPlaybackRateCol = cols.first { $0["name"] as? String == "defaultPlaybackRate" }
      #expect(defaultPlaybackRateCol != nil)
      let type = defaultPlaybackRateCol?["type"] as? String
      #expect(type == "DOUBLE", "defaultPlaybackRate should be DOUBLE type")
    }

    // Test that existing podcast has NULL defaultPlaybackRate after migration
    try await appDB.db.read { db in
      if let row = try Row.fetchOne(
        db,
        sql: "SELECT defaultPlaybackRate FROM podcast WHERE id = ?",
        arguments: [testPodcastID]
      ) {
        let isNull = row.hasNull(atIndex: 0)
        #expect(isNull, "Existing podcast should have NULL defaultPlaybackRate after migration")
      }
    }

    // Test valid values within range (0.8 to 2.0)
    try await appDB.db.write { db in
      // Test minimum valid value
      try db.execute(
        sql: """
          INSERT INTO podcast (feedURL, title, image, description, defaultPlaybackRate)
          VALUES (?, ?, ?, ?, ?)
          """,
        arguments: [
          "https://example.com/feed1.xml",
          "Podcast 1x",
          "https://example.com/image1.jpg",
          "Test 1x",
          0.8,
        ]
      )

      // Test maximum valid value
      try db.execute(
        sql: """
          INSERT INTO podcast (feedURL, title, image, description, defaultPlaybackRate)
          VALUES (?, ?, ?, ?, ?)
          """,
        arguments: [
          "https://example.com/feed2.xml",
          "Podcast 2x",
          "https://example.com/image2.jpg",
          "Test 2x",
          2.0,
        ]
      )

      // Test normal value
      try db.execute(
        sql: """
          INSERT INTO podcast (feedURL, title, image, description, defaultPlaybackRate)
          VALUES (?, ?, ?, ?, ?)
          """,
        arguments: [
          "https://example.com/feed3.xml",
          "Podcast 1.5x",
          "https://example.com/image3.jpg",
          "Test 1.5x",
          1.5,
        ]
      )

      // Test NULL value
      try db.execute(
        sql: """
          INSERT INTO podcast (feedURL, title, image, description, defaultPlaybackRate)
          VALUES (?, ?, ?, ?, ?)
          """,
        arguments: [
          "https://example.com/feed4.xml",
          "Podcast NULL",
          "https://example.com/image4.jpg",
          "Test NULL",
          nil,
        ]
      )
    }

    // Verify valid values were inserted
    let validCount = try await appDB.db.read { db in
      try Int.fetchOne(
        db,
        sql:
          "SELECT COUNT(*) FROM podcast WHERE defaultPlaybackRate IS NOT NULL AND defaultPlaybackRate >= 0.8 AND defaultPlaybackRate <= 2.0"
      )
    }
    #expect(validCount == 3, "Should have 3 podcasts with valid defaultPlaybackRate values")

    // Test that value below minimum (0.8) is rejected
    await #expect(throws: DatabaseError.self) {
      try await self.appDB.db.write { db in
        try db.execute(
          sql: """
            INSERT INTO podcast (feedURL, title, image, description, defaultPlaybackRate)
            VALUES (?, ?, ?, ?, ?)
            """,
          arguments: [
            "https://example.com/feed-low.xml",
            "Podcast Too Slow",
            "https://example.com/image-low.jpg",
            "Test Too Slow",
            0.7,
          ]
        )
      }
    }

    // Test that value above maximum (2.0) is rejected
    await #expect(throws: DatabaseError.self) {
      try await self.appDB.db.write { db in
        try db.execute(
          sql: """
            INSERT INTO podcast (feedURL, title, image, description, defaultPlaybackRate)
            VALUES (?, ?, ?, ?, ?)
            """,
          arguments: [
            "https://example.com/feed-high.xml",
            "Podcast Too Fast",
            "https://example.com/image-high.jpg",
            "Test Too Fast",
            2.1,
          ]
        )
      }
    }

    // Test that updating to invalid values is also rejected
    await #expect(throws: DatabaseError.self) {
      try await self.appDB.db.write { db in
        try db.execute(
          sql: "UPDATE podcast SET defaultPlaybackRate = ? WHERE id = ?",
          arguments: [0.5, testPodcastID]
        )
      }
    }

    await #expect(throws: DatabaseError.self) {
      try await self.appDB.db.write { db in
        try db.execute(
          sql: "UPDATE podcast SET defaultPlaybackRate = ? WHERE id = ?",
          arguments: [3.0, testPodcastID]
        )
      }
    }

    // Test that updating to valid values works
    try await appDB.db.write { db in
      try db.execute(
        sql: "UPDATE podcast SET defaultPlaybackRate = ? WHERE id = ?",
        arguments: [1.25, testPodcastID]
      )
    }

    let updatedRate = try await appDB.db.read { db in
      try Double.fetchOne(
        db,
        sql: "SELECT defaultPlaybackRate FROM podcast WHERE id = ?",
        arguments: [testPodcastID]
      )
    }
    #expect(updatedRate == 1.25, "Podcast should have updated defaultPlaybackRate of 1.25")
  }
}
