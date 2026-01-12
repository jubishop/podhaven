// Copyright Justin Bishop, 2025

import Foundation
import GRDB
import Testing

@testable import PodHaven

@Suite("v23 migration tests", .container)
class V23MigrationTests {
  private let appDB = AppDB.inMemory(migrate: false)
  private let migrator: DatabaseMigrator

  init() async throws {
    self.migrator = try Schema.makeMigrator()
  }

  @Test("v23 migration converts cacheAllEpisodes from BOOLEAN to TEXT enum")
  func testV23Migration() async throws {
    // Apply migrations up to v22
    try migrator.migrate(appDB.db, upTo: "v22")

    // Insert test podcasts before migration with different boolean values
    let truePodcastID = try await appDB.db.write { db in
      try db.execute(
        sql: """
          INSERT INTO podcast (feedURL, title, image, description, cacheAllEpisodes)
          VALUES (?, ?, ?, ?, ?)
          """,
        arguments: [
          "https://example.com/feed-true.xml",
          "Podcast True",
          "https://example.com/image-true.jpg",
          "Test True",
          true,
        ]
      )
      return db.lastInsertedRowID
    }

    let falsePodcastID = try await appDB.db.write { db in
      try db.execute(
        sql: """
          INSERT INTO podcast (feedURL, title, image, description, cacheAllEpisodes)
          VALUES (?, ?, ?, ?, ?)
          """,
        arguments: [
          "https://example.com/feed-false.xml",
          "Podcast False",
          "https://example.com/image-false.jpg",
          "Test False",
          false,
        ]
      )
      return db.lastInsertedRowID
    }

    // Verify cacheAllEpisodes column is BOOLEAN before migration
    try await appDB.db.read { db in
      let cols = try Row.fetchAll(db, sql: "PRAGMA table_info('podcast')")
      let cacheAllEpisodesCol = cols.first { $0["name"] as? String == "cacheAllEpisodes" }
      #expect(cacheAllEpisodesCol != nil)
      let type = cacheAllEpisodesCol?["type"] as? String
      #expect(type == "BOOLEAN", "cacheAllEpisodes should be BOOLEAN type before v23")
    }

    // Verify data before migration
    let trueBoolValue = try await appDB.db.read { db in
      try Bool.fetchOne(
        db,
        sql: "SELECT cacheAllEpisodes FROM podcast WHERE id = ?",
        arguments: [truePodcastID]
      )
    }
    #expect(trueBoolValue == true, "Podcast should have true cacheAllEpisodes before migration")

    let falseBoolValue = try await appDB.db.read { db in
      try Bool.fetchOne(
        db,
        sql: "SELECT cacheAllEpisodes FROM podcast WHERE id = ?",
        arguments: [falsePodcastID]
      )
    }
    #expect(falseBoolValue == false, "Podcast should have false cacheAllEpisodes before migration")

    // Apply v23 migration
    try migrator.migrate(appDB.db, upTo: "v23")

    // Verify cacheAllEpisodes column is now TEXT after migration
    try await appDB.db.read { db in
      let cols = try Row.fetchAll(db, sql: "PRAGMA table_info('podcast')")
      let cacheAllEpisodesCol = cols.first { $0["name"] as? String == "cacheAllEpisodes" }
      #expect(cacheAllEpisodesCol != nil)
      let type = cacheAllEpisodesCol?["type"] as? String
      #expect(type == "TEXT", "cacheAllEpisodes should be TEXT type after v23")

      // Verify it's NOT NULL
      let notNull = cacheAllEpisodesCol?["notnull"] as? Int64
      #expect(notNull == 1, "cacheAllEpisodes should be NOT NULL")

      // Verify default value
      let dfltValue = cacheAllEpisodesCol?["dflt_value"] as? String
      #expect(dfltValue == "'never'", "cacheAllEpisodes should have default value of 'never'")
    }

    // Verify data was converted correctly: true -> 'cache'
    let trueTextValue = try await appDB.db.read { db in
      try String.fetchOne(
        db,
        sql: "SELECT cacheAllEpisodes FROM podcast WHERE id = ?",
        arguments: [truePodcastID]
      )
    }
    #expect(
      trueTextValue == "cache",
      "Podcast with true should have 'cache' after migration"
    )

    // Verify data was converted correctly: false -> 'never'
    let falseTextValue = try await appDB.db.read { db in
      try String.fetchOne(
        db,
        sql: "SELECT cacheAllEpisodes FROM podcast WHERE id = ?",
        arguments: [falsePodcastID]
      )
    }
    #expect(
      falseTextValue == "never",
      "Podcast with false should have 'never' after migration"
    )

    // Test inserting new podcasts with different enum values
    try await appDB.db.write { db in
      // Test 'cache' value
      try db.execute(
        sql: """
          INSERT INTO podcast (feedURL, title, image, description, cacheAllEpisodes)
          VALUES (?, ?, ?, ?, ?)
          """,
        arguments: [
          "https://example.com/feed1.xml",
          "Podcast Cache",
          "https://example.com/image1.jpg",
          "Test Cache",
          "cache",
        ]
      )

      // Test 'save' value
      try db.execute(
        sql: """
          INSERT INTO podcast (feedURL, title, image, description, cacheAllEpisodes)
          VALUES (?, ?, ?, ?, ?)
          """,
        arguments: [
          "https://example.com/feed2.xml",
          "Podcast Save",
          "https://example.com/image2.jpg",
          "Test Save",
          "save",
        ]
      )

      // Test 'never' value
      try db.execute(
        sql: """
          INSERT INTO podcast (feedURL, title, image, description, cacheAllEpisodes)
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
    let cacheCount = try await appDB.db.read { db in
      try Int.fetchOne(
        db,
        sql: "SELECT COUNT(*) FROM podcast WHERE cacheAllEpisodes = ?",
        arguments: ["cache"]
      )
    }
    #expect(cacheCount == 2, "Should have 2 podcasts with cacheAllEpisodes = 'cache'")

    let saveCount = try await appDB.db.read { db in
      try Int.fetchOne(
        db,
        sql: "SELECT COUNT(*) FROM podcast WHERE cacheAllEpisodes = ?",
        arguments: ["save"]
      )
    }
    #expect(saveCount == 1, "Should have 1 podcast with cacheAllEpisodes = 'save'")

    let neverCount = try await appDB.db.read { db in
      try Int.fetchOne(
        db,
        sql: "SELECT COUNT(*) FROM podcast WHERE cacheAllEpisodes = ?",
        arguments: ["never"]
      )
    }
    #expect(neverCount == 3, "Should have 3 podcasts with cacheAllEpisodes = 'never'")

    // Test that NULL value is rejected (NOT NULL constraint)
    await #expect(throws: DatabaseError.self) {
      try await self.appDB.db.write { db in
        try db.execute(
          sql: """
            INSERT INTO podcast (feedURL, title, image, description, cacheAllEpisodes)
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
        sql: "UPDATE podcast SET cacheAllEpisodes = ? WHERE id = ?",
        arguments: ["save", truePodcastID]
      )
    }

    let updatedValue = try await appDB.db.read { db in
      try String.fetchOne(
        db,
        sql: "SELECT cacheAllEpisodes FROM podcast WHERE id = ?",
        arguments: [truePodcastID]
      )
    }
    #expect(
      updatedValue == "save",
      "Podcast should have updated cacheAllEpisodes of 'save'"
    )
  }
}
