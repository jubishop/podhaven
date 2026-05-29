// Copyright Justin Bishop, 2026

import Foundation
import GRDB
import Testing

@testable import PodHaven

@Suite("of v34 migration tests", .container)
class V34MigrationTests {
  private let appDB = AppDB.inMemory(migrate: false)
  private let migrator: DatabaseMigrator

  init() async throws {
    self.migrator = Schema.makeMigrator()
  }

  @Test("v34 adds maxPlaybackTime column seeded from currentTime")
  func testV34Migration() async throws {
    try migrator.migrate(appDB.unsafeTestDB, upTo: "v33")

    let podcastID = try await appDB.unsafeTestDB.write { db in
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

    // Seed three episodes: in-progress, untouched, and finished (currentTime 0).
    let inProgressID = try await appDB.unsafeTestDB.write { db in
      try db.execute(
        sql: """
          INSERT INTO episode (podcastId, guid, mediaURL, title, pubDate, currentTime)
          VALUES (?, ?, ?, ?, ?, ?)
          """,
        arguments: [
          podcastID, "guid-in-progress", "https://example.com/ep1.mp3",
          "In Progress", Date(), 123.5,
        ]
      )
      return db.lastInsertedRowID
    }
    let untouchedID = try await appDB.unsafeTestDB.write { db in
      try db.execute(
        sql: """
          INSERT INTO episode (podcastId, guid, mediaURL, title, pubDate)
          VALUES (?, ?, ?, ?, ?)
          """,
        arguments: [
          podcastID, "guid-untouched", "https://example.com/ep2.mp3",
          "Untouched", Date(),
        ]
      )
      return db.lastInsertedRowID
    }
    let finishedID = try await appDB.unsafeTestDB.write { db in
      try db.execute(
        sql: """
          INSERT INTO episode (
            podcastId, guid, mediaURL, title, pubDate, currentTime, finishDate
          ) VALUES (?, ?, ?, ?, ?, ?, ?)
          """,
        arguments: [
          podcastID, "guid-finished", "https://example.com/ep3.mp3",
          "Finished", Date(), 0, Date(),
        ]
      )
      return db.lastInsertedRowID
    }

    try await appDB.unsafeTestDB.read { db in
      let cols = try Row.fetchAll(db, sql: "PRAGMA table_info('episode')")
      let colNames = Set(cols.compactMap { $0["name"] as? String })
      #expect(!colNames.contains("maxPlaybackTime"), "maxPlaybackTime should not exist before v34")
    }

    try migrator.migrate(appDB.unsafeTestDB, upTo: "v34")

    try await appDB.unsafeTestDB.read { db in
      let cols = try Row.fetchAll(db, sql: "PRAGMA table_info('episode')")
      let col = cols.first { $0["name"] as? String == "maxPlaybackTime" }
      #expect(col != nil, "maxPlaybackTime column should exist after v34")
      #expect(col?["type"] as? String == "INTEGER")
      #expect(col?["notnull"] as? Int64 == 1, "maxPlaybackTime should be NOT NULL")
      #expect(col?["dflt_value"] as? String == "0", "maxPlaybackTime should default to 0")
    }

    // Backfill sets maxPlaybackTime to the episode's existing currentTime.
    try await appDB.unsafeTestDB.read { db in
      let inProgress = try Double.fetchOne(
        db,
        sql: "SELECT maxPlaybackTime FROM episode WHERE id = ?",
        arguments: [inProgressID]
      )
      #expect(inProgress == 123.5)

      let untouched = try Double.fetchOne(
        db,
        sql: "SELECT maxPlaybackTime FROM episode WHERE id = ?",
        arguments: [untouchedID]
      )
      #expect(untouched == 0)

      let finished = try Double.fetchOne(
        db,
        sql: "SELECT maxPlaybackTime FROM episode WHERE id = ?",
        arguments: [finishedID]
      )
      #expect(finished == 0)
    }

    // New inserts without the column default to 0.
    let freshID = try await appDB.unsafeTestDB.write { db in
      try db.execute(
        sql: """
          INSERT INTO episode (podcastId, guid, mediaURL, title, pubDate)
          VALUES (?, ?, ?, ?, ?)
          """,
        arguments: [
          podcastID, "guid-fresh", "https://example.com/ep4.mp3",
          "Fresh", Date(),
        ]
      )
      return db.lastInsertedRowID
    }
    let fresh = try await appDB.unsafeTestDB.read { db in
      try Double.fetchOne(
        db,
        sql: "SELECT maxPlaybackTime FROM episode WHERE id = ?",
        arguments: [freshID]
      )
    }
    #expect(fresh == 0)
  }
}
