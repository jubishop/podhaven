// Copyright Justin Bishop, 2026

import Foundation
import GRDB
import Testing

@testable import PodHaven

@Suite("of v28 migration tests", .container)
class V28MigrationTests {
  private let appDB = AppDB.inMemory(migrate: false)
  private let migrator: DatabaseMigrator

  init() async throws {
    self.migrator = Schema.makeMigrator()
  }

  @Test("v28 migration adds episodeTag table with indexes and constraints")
  func testV28Migration() async throws {
    try migrator.migrate(appDB.unsafeTestDB, upTo: "v27")

    try await appDB.unsafeTestDB.read { db in
      let tableNames = Set(
        try String.fetchAll(
          db,
          sql: "SELECT name FROM sqlite_master WHERE type = 'table'"
        )
      )
      #expect(!tableNames.contains("episodeTag"))
    }

    try migrator.migrate(appDB.unsafeTestDB, upTo: "v28")

    try await appDB.unsafeTestDB.read { db in
      let tableNames = Set(
        try String.fetchAll(
          db,
          sql: "SELECT name FROM sqlite_master WHERE type = 'table'"
        )
      )
      #expect(tableNames.contains("episodeTag"))

      let cols = try Row.fetchAll(db, sql: "PRAGMA table_info('episodeTag')")
      let colNames = Set(cols.compactMap { $0["name"] as? String })
      #expect(colNames == Set(["episodeId", "tagId"]))

      let indexes = try Row.fetchAll(
        db,
        sql: "SELECT name FROM sqlite_master WHERE type = 'index'"
      )
      let indexNames = Set(indexes.compactMap { $0["name"] as? String })
      #expect(indexNames.contains("episodeTag_on_episodeId"))
      #expect(indexNames.contains("episodeTag_on_tagId"))
    }

    let (episodeID, tagID) = try await appDB.unsafeTestDB.write { db in
      try db.execute(
        sql: """
          INSERT INTO podcast (feedURL, title, image, description)
          VALUES (?, ?, ?, ?)
          """,
        arguments: [
          "https://example.com/feed.xml",
          "Example",
          "https://example.com/image.png",
          "Description",
        ]
      )
      let podcastID = db.lastInsertedRowID

      try db.execute(
        sql: """
          INSERT INTO episode (podcastId, guid, mediaURL, title, pubDate, duration, currentTime, saveInCache)
          VALUES (?, ?, ?, ?, ?, ?, ?, ?)
          """,
        arguments: [
          podcastID,
          "guid-1",
          "https://example.com/ep1.mp3",
          "Episode 1",
          "2026-01-01",
          0,
          0,
          false,
        ]
      )
      let episodeID = db.lastInsertedRowID

      try db.execute(
        sql: """
          INSERT INTO tag (name)
          VALUES (?)
          """,
        arguments: ["Tech"]
      )
      let tagID = db.lastInsertedRowID

      return (episodeID, tagID)
    }

    try await appDB.unsafeTestDB.write { db in
      try db.execute(
        sql: """
          INSERT INTO episodeTag (episodeId, tagId)
          VALUES (?, ?)
          """,
        arguments: [episodeID, tagID]
      )
    }

    await #expect(throws: DatabaseError.self) {
      try await self.appDB.unsafeTestDB.write { db in
        try db.execute(
          sql: """
            INSERT INTO episodeTag (episodeId, tagId)
            VALUES (?, ?)
            """,
          arguments: [episodeID, tagID]
        )
      }
    }

    try await appDB.unsafeTestDB.read { db in
      let mappingCount = try Int.fetchOne(
        db,
        sql: """
          SELECT COUNT(*)
          FROM episodeTag
          WHERE episodeId = ? AND tagId = ?
          """,
        arguments: [episodeID, tagID]
      )
      #expect(mappingCount == 1)
    }

    try await appDB.unsafeTestDB.write { db in
      try db.execute(
        sql: "DELETE FROM tag WHERE id = ?",
        arguments: [tagID]
      )
    }

    try await appDB.unsafeTestDB.read { db in
      let remainingMappings = try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM episodeTag")
      #expect(remainingMappings == 0)
    }
  }
}
