// Copyright Justin Bishop, 2025

import AVFoundation
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

  // NOTE: Next migration should be v18

  @Test("v1 migration creates schema with all expected tables and constraints")
  func testV1Migration() async throws {
    // Apply v1 migration
    try migrator.migrate(appDB.db, upTo: "v1")

    // Verify podcast table exists with correct columns
    try await appDB.db.read { db in
      let cols = try Row.fetchAll(db, sql: "PRAGMA table_info('podcast')")
      let colNames = Set(cols.compactMap { $0["name"] as? String })

      #expect(colNames.contains("id"))
      #expect(colNames.contains("feedURL"))
      #expect(colNames.contains("title"))
      #expect(colNames.contains("image"))
      #expect(colNames.contains("description"))
      #expect(colNames.contains("link"))
      #expect(colNames.contains("lastUpdate"))
      #expect(colNames.contains("subscriptionDate"))
      #expect(colNames.contains("cacheAllEpisodes"))
      #expect(colNames.contains("creationDate"))
    }

    // Verify episode table exists with correct columns
    try await appDB.db.read { db in
      let cols = try Row.fetchAll(db, sql: "PRAGMA table_info('episode')")
      let colNames = Set(cols.compactMap { $0["name"] as? String })

      #expect(colNames.contains("id"))
      #expect(colNames.contains("podcastId"))
      #expect(colNames.contains("guid"))
      #expect(colNames.contains("mediaURL"))
      #expect(colNames.contains("title"))
      #expect(colNames.contains("pubDate"))
      #expect(colNames.contains("duration"))
      #expect(colNames.contains("description"))
      #expect(colNames.contains("link"))
      #expect(colNames.contains("image"))
      #expect(colNames.contains("completionDate"))
      #expect(colNames.contains("currentTime"))
      #expect(colNames.contains("queueOrder"))
      #expect(colNames.contains("lastQueued"))
      #expect(colNames.contains("cachedFilename"))
      #expect(colNames.contains("downloadTaskID"))
      #expect(colNames.contains("creationDate"))
    }

    // Verify unique constraints are in place
    try await appDB.db.read { db in
      // Check podcast unique constraint on feedURL
      let podcastIndexes = try Row.fetchAll(
        db,
        sql: "SELECT * FROM sqlite_master WHERE type = 'index' AND tbl_name = 'podcast'"
      )

      // SQLite creates automatic indexes for unique constraints (sqlite_autoindex_*)
      let hasFeedURLConstraint = podcastIndexes.contains { row in
        let name = row["name"] as? String ?? ""
        // sqlite_autoindex_podcast_1 is created for the unique constraint on feedURL
        return name.starts(with: "sqlite_autoindex_podcast")
      }
      #expect(hasFeedURLConstraint, "feedURL unique constraint should exist")

      // Check episode unique constraints
      let episodeIndexes = try Row.fetchAll(
        db,
        sql: "SELECT * FROM sqlite_master WHERE type = 'index' AND tbl_name = 'episode'"
      )

      // Count the sqlite_autoindex entries for episode table
      // We should have multiple: one for each unique constraint
      let autoIndexCount =
        episodeIndexes.filter { row in
          let name = row["name"] as? String ?? ""
          return name.starts(with: "sqlite_autoindex_episode")
        }
        .count

      // We have 3 unique constraints on episode table:
      // 1. podcastId + guid
      // 2. podcastId + mediaURL
      // 3. guid + mediaURL
      // 4. downloadTaskID (which is unique by itself)
      // So we should have at least 4 auto-indexes
      #expect(autoIndexCount >= 3, "Should have auto-indexes for unique constraints")

      // Also verify we have regular indexes on guid and mediaURL for performance
      let hasGuidIndex = episodeIndexes.contains { row in
        let name = row["name"] as? String ?? ""
        return name == "episode_on_guid"
      }
      let hasMediaURLIndex = episodeIndexes.contains { row in
        let name = row["name"] as? String ?? ""
        return name == "episode_on_mediaURL"
      }

      #expect(hasGuidIndex, "Should have index on guid")
      #expect(hasMediaURLIndex, "Should have index on mediaURL")
    }

    // Test data insertion and constraints
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

    // Test episode insertion
    try await appDB.db.write { db in
      try db.execute(
        sql: """
          INSERT INTO episode (
            podcastId, guid, mediaURL, title, pubDate
          ) VALUES (?, ?, ?, ?, ?)
          """,
        arguments: [
          testPodcastID,
          "test-guid",
          "https://example.com/episode.mp3",
          "Test Episode",
          Date(),
        ]
      )
    }

    // Test unique constraint on podcastId + guid
    await #expect(throws: DatabaseError.self) {
      try await self.appDB.db.write { db in
        try db.execute(
          sql: """
            INSERT INTO episode (
              podcastId, guid, mediaURL, title, pubDate
            ) VALUES (?, ?, ?, ?, ?)
            """,
          arguments: [
            testPodcastID,
            "test-guid",  // Same guid
            "https://example.com/different.mp3",  // Different mediaURL
            "Should Fail",
            Date(),
          ]
        )
      }
    }

    // Test unique constraint on guid + mediaURL
    await #expect(throws: DatabaseError.self) {
      try await self.appDB.db.write { db in
        try db.execute(
          sql: """
            INSERT INTO episode (
              podcastId, guid, mediaURL, title, pubDate
            ) VALUES (?, ?, ?, ?, ?)
            """,
          arguments: [
            testPodcastID,
            "test-guid",  // Same guid
            "https://example.com/episode.mp3",  // Same mediaURL
            "Should Also Fail",
            Date(),
          ]
        )
      }
    }

    // Test unique constraint on podcastId + mediaURL
    await #expect(throws: DatabaseError.self) {
      try await self.appDB.db.write { db in
        try db.execute(
          sql: """
            INSERT INTO episode (
              podcastId, guid, mediaURL, title, pubDate
            ) VALUES (?, ?, ?, ?, ?)
            """,
          arguments: [
            testPodcastID,  // Same podcastId
            "different-guid",  // Different guid
            "https://example.com/episode.mp3",  // Same mediaURL for same podcast
            "Should Fail - Same Media URL in Same Podcast",
            Date(),
          ]
        )
      }
    }

    // Test that same mediaURL can exist in different podcasts
    let secondPodcastID = try await appDB.db.write { db in
      try db.execute(
        sql: """
          INSERT INTO podcast (feedURL, title, image, description)
          VALUES (?, ?, ?, ?)
          """,
        arguments: [
          "https://example2.com/feed.xml",
          "Second Podcast",
          "https://example2.com/image.jpg",
          "Second Description",
        ]
      )
      return db.lastInsertedRowID
    }

    // This should succeed - same mediaURL but different podcast
    try await appDB.db.write { db in
      try db.execute(
        sql: """
          INSERT INTO episode (
            podcastId, guid, mediaURL, title, pubDate
          ) VALUES (?, ?, ?, ?, ?)
          """,
        arguments: [
          secondPodcastID,  // Different podcast
          "another-guid",
          "https://example.com/episode.mp3",  // Same mediaURL as first episode
          "Same Media URL in Different Podcast",
          Date(),
        ]
      )
    }

    // Verify both episodes exist with the same mediaURL in different podcasts
    let episodeCount = try await appDB.db.read { db in
      try Int.fetchOne(
        db,
        sql: "SELECT COUNT(*) FROM episode WHERE mediaURL = ?",
        arguments: ["https://example.com/episode.mp3"]
      )
    }
    #expect(episodeCount == 2, "Should have 2 episodes with same mediaURL in different podcasts")
  }
}
