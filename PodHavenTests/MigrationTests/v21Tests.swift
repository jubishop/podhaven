// Copyright Justin Bishop, 2025

import Foundation
import GRDB
import Testing

@testable import PodHaven

@Suite("v21 migration tests", .container)
class V21MigrationTests {
  private let appDB = AppDB.inMemory(migrate: false)
  private let migrator: DatabaseMigrator

  init() async throws {
    self.migrator = try Schema.makeMigrator()
  }

  @Test("v21 migration adds queueAllEpisodes column to podcast table with default value")
  func testV21Migration() async throws {
    // Apply migrations up to v20
    try migrator.migrate(appDB.db, upTo: "v20")

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

    // Verify queueAllEpisodes column doesn't exist yet
    try await appDB.db.read { db in
      let cols = try Row.fetchAll(db, sql: "PRAGMA table_info('podcast')")
      let colNames = Set(cols.compactMap { $0["name"] as? String })
      #expect(
        !colNames.contains("queueAllEpisodes"),
        "queueAllEpisodes column should not exist before v21"
      )
    }

    // Apply v21 migration
    try migrator.migrate(appDB.db, upTo: "v21")

    // Verify queueAllEpisodes column exists after migration
    try await appDB.db.read { db in
      let cols = try Row.fetchAll(db, sql: "PRAGMA table_info('podcast')")
      let colNames = Set(cols.compactMap { $0["name"] as? String })
      #expect(
        colNames.contains("queueAllEpisodes"),
        "queueAllEpisodes column should exist after v21"
      )

      // Verify it's a TEXT type
      let queueAllEpisodesCol = cols.first { $0["name"] as? String == "queueAllEpisodes" }
      #expect(queueAllEpisodesCol != nil)
      let type = queueAllEpisodesCol?["type"] as? String
      #expect(type == "TEXT", "queueAllEpisodes should be TEXT type")

      // Verify it's NOT NULL
      let notNull = queueAllEpisodesCol?["notnull"] as? Int64
      #expect(notNull == 1, "queueAllEpisodes should be NOT NULL")

      // Verify default value
      let dfltValue = queueAllEpisodesCol?["dflt_value"] as? String
      #expect(dfltValue == "'never'", "queueAllEpisodes should have default value of 'never'")
    }

    // Test that existing podcast has 'never' as default value after migration
    try await appDB.db.read { db in
      if let queueAllEpisodes = try String.fetchOne(
        db,
        sql: "SELECT queueAllEpisodes FROM podcast WHERE id = ?",
        arguments: [testPodcastID]
      ) {
        #expect(
          queueAllEpisodes == "never",
          "Existing podcast should have 'never' as queueAllEpisodes after migration"
        )
      }
    }

    // Test inserting podcasts with different queueAllEpisodes values
    try await appDB.db.write { db in
      // Test 'onTop' value
      try db.execute(
        sql: """
          INSERT INTO podcast (feedURL, title, image, description, queueAllEpisodes)
          VALUES (?, ?, ?, ?, ?)
          """,
        arguments: [
          "https://example.com/feed1.xml",
          "Podcast OnTop",
          "https://example.com/image1.jpg",
          "Test OnTop",
          "onTop",
        ]
      )

      // Test 'onBottom' value
      try db.execute(
        sql: """
          INSERT INTO podcast (feedURL, title, image, description, queueAllEpisodes)
          VALUES (?, ?, ?, ?, ?)
          """,
        arguments: [
          "https://example.com/feed2.xml",
          "Podcast OnBottom",
          "https://example.com/image2.jpg",
          "Test OnBottom",
          "onBottom",
        ]
      )

      // Test 'never' value
      try db.execute(
        sql: """
          INSERT INTO podcast (feedURL, title, image, description, queueAllEpisodes)
          VALUES (?, ?, ?, ?, ?)
          """,
        arguments: [
          "https://example.com/feed3.xml",
          "Podcast Never",
          "https://example.com/image3.jpg",
          "Test Never",
          "never",
        ]
      )

      // Test default value (should be 'never')
      try db.execute(
        sql: """
          INSERT INTO podcast (feedURL, title, image, description)
          VALUES (?, ?, ?, ?)
          """,
        arguments: [
          "https://example.com/feed4.xml",
          "Podcast Default",
          "https://example.com/image4.jpg",
          "Test Default",
        ]
      )
    }

    // Verify all values were inserted correctly
    let onTopCount = try await appDB.db.read { db in
      try Int.fetchOne(
        db,
        sql: "SELECT COUNT(*) FROM podcast WHERE queueAllEpisodes = ?",
        arguments: ["onTop"]
      )
    }
    #expect(onTopCount == 1, "Should have 1 podcast with queueAllEpisodes = 'onTop'")

    let onBottomCount = try await appDB.db.read { db in
      try Int.fetchOne(
        db,
        sql: "SELECT COUNT(*) FROM podcast WHERE queueAllEpisodes = ?",
        arguments: ["onBottom"]
      )
    }
    #expect(onBottomCount == 1, "Should have 1 podcast with queueAllEpisodes = 'onBottom'")

    let neverCount = try await appDB.db.read { db in
      try Int.fetchOne(
        db,
        sql: "SELECT COUNT(*) FROM podcast WHERE queueAllEpisodes = ?",
        arguments: ["never"]
      )
    }
    #expect(neverCount == 3, "Should have 3 podcasts with queueAllEpisodes = 'never'")

    // Test that NULL value is rejected (NOT NULL constraint)
    await #expect(throws: DatabaseError.self) {
      try await self.appDB.db.write { db in
        try db.execute(
          sql: """
            INSERT INTO podcast (feedURL, title, image, description, queueAllEpisodes)
            VALUES (?, ?, ?, ?, ?)
            """,
          arguments: [
            "https://example.com/feed-null.xml",
            "Podcast NULL",
            "https://example.com/image-null.jpg",
            "Test NULL",
            nil,
          ]
        )
      }
    }

    // Test updating to valid values works
    try await appDB.db.write { db in
      try db.execute(
        sql: "UPDATE podcast SET queueAllEpisodes = ? WHERE id = ?",
        arguments: ["onTop", testPodcastID]
      )
    }

    let updatedValue = try await appDB.db.read { db in
      try String.fetchOne(
        db,
        sql: "SELECT queueAllEpisodes FROM podcast WHERE id = ?",
        arguments: [testPodcastID]
      )
    }
    #expect(
      updatedValue == "onTop",
      "Podcast should have updated queueAllEpisodes of 'onTop'"
    )
  }
}
