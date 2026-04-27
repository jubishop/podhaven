// Copyright Justin Bishop, 2026

import Foundation
import GRDB
import Testing

@testable import PodHaven

@Suite("of v40 migration tests", .container)
class V40MigrationTests {
  private let appDB = AppDB.inMemory(migrate: false)
  private let migrator: DatabaseMigrator

  init() async throws {
    self.migrator = Schema.makeMigrator()
  }

  @Test("v40 adds nullable playbackCoverage and lastPlayedDate columns")
  func columnsAdded() async throws {
    try migrator.migrate(appDB.db, upTo: "v39")

    try await appDB.db.read { db in
      let names = try Set(
        Row.fetchAll(db, sql: "PRAGMA table_info('episode')").compactMap {
          $0["name"] as? String
        }
      )
      #expect(!names.contains("playbackCoverage"))
      #expect(!names.contains("lastPlayedDate"))
    }

    try migrator.migrate(appDB.db, upTo: "v40")

    try await appDB.db.read { db in
      let cols = try Row.fetchAll(db, sql: "PRAGMA table_info('episode')")
      let coverage = try #require(cols.first { $0["name"] as? String == "playbackCoverage" })
      #expect(coverage["type"] as? String == "BLOB")
      #expect((coverage["notnull"] as? Int64 ?? 0) == 0)

      let lastPlayed = try #require(cols.first { $0["name"] as? String == "lastPlayedDate" })
      #expect(lastPlayed["type"] as? String == "DATETIME")
      #expect((lastPlayed["notnull"] as? Int64 ?? 0) == 0)
    }
  }

  @Test("v40 leaves existing rows with null playbackCoverage and lastPlayedDate")
  func existingRowsAreNull() async throws {
    try migrator.migrate(appDB.db, upTo: "v39")

    let podcastID = try await appDB.db.write { db in
      try db.execute(
        sql: """
          INSERT INTO podcast (feedURL, title, image, description)
          VALUES (?, ?, ?, ?)
          """,
        arguments: ["https://example.com/feed.xml", "p", "img", "desc"]
      )
      return db.lastInsertedRowID
    }

    let episodeID = try await appDB.db.write { db in
      try db.execute(
        sql: """
          INSERT INTO episode (podcastId, guid, mediaURL, title, pubDate, currentTime)
          VALUES (?, ?, ?, ?, ?, ?)
          """,
        arguments: [podcastID, "g", "https://example.com/m.mp3", "ep", Date(), 42]
      )
      return db.lastInsertedRowID
    }

    try migrator.migrate(appDB.db, upTo: "v40")

    try await appDB.db.read { db in
      let row = try #require(
        try Row.fetchOne(
          db,
          sql: "SELECT playbackCoverage, lastPlayedDate FROM episode WHERE id = ?",
          arguments: [episodeID]
        )
      )
      #expect((row["playbackCoverage"] as Data?) == nil)
      #expect((row["lastPlayedDate"] as Date?) == nil)
    }
  }

  @Test("v40 accepts BLOB writes to playbackCoverage and DATETIME writes to lastPlayedDate")
  func acceptsWrites() async throws {
    try migrator.migrate(appDB.db, upTo: "v40")

    let podcastID = try await appDB.db.write { db in
      try db.execute(
        sql: """
          INSERT INTO podcast (feedURL, title, image, description)
          VALUES (?, ?, ?, ?)
          """,
        arguments: ["https://example.com/feed.xml", "p", "img", "desc"]
      )
      return db.lastInsertedRowID
    }

    let now = Date()
    let bitmap = Data([0xFF, 0x0F, 0xA5])

    let episodeID = try await appDB.db.write { db in
      try db.execute(
        sql: """
          INSERT INTO episode (
            podcastId, guid, mediaURL, title, pubDate,
            playbackCoverage, lastPlayedDate
          )
          VALUES (?, ?, ?, ?, ?, ?, ?)
          """,
        arguments: [
          podcastID, "g", "https://example.com/m.mp3", "ep", now, bitmap, now,
        ]
      )
      return db.lastInsertedRowID
    }

    try await appDB.db.read { db in
      let row = try #require(
        try Row.fetchOne(
          db,
          sql: "SELECT playbackCoverage, lastPlayedDate FROM episode WHERE id = ?",
          arguments: [episodeID]
        )
      )
      #expect((row["playbackCoverage"] as Data?) == bitmap)
      let storedDate = try #require(row["lastPlayedDate"] as Date?)
      #expect(abs(storedDate.timeIntervalSince(now)) < 1.0)
    }
  }
}
