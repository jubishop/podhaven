// Copyright Justin Bishop, 2026

import Foundation
import GRDB
import Testing

@testable import PodHaven

@Suite("of v27 migration tests", .container)
class V27MigrationTests {
  private let appDB = AppDB.inMemory(migrate: false)
  private let migrator: DatabaseMigrator

  init() async throws {
    self.migrator = Schema.makeMigrator()
  }

  @Test("v27 migration adds tag and podcastTag tables with indexes and constraints")
  func testV27Migration() async throws {
    try migrator.migrate(appDB.db, upTo: "v26")

    try await appDB.db.read { db in
      let tableNames = Set(
        try String.fetchAll(
          db,
          sql: "SELECT name FROM sqlite_master WHERE type = 'table'"
        )
      )
      #expect(!tableNames.contains("tag"))
      #expect(!tableNames.contains("podcastTag"))
    }

    try migrator.migrate(appDB.db, upTo: "v27")

    try await appDB.db.read { db in
      let tableNames = Set(
        try String.fetchAll(
          db,
          sql: "SELECT name FROM sqlite_master WHERE type = 'table'"
        )
      )
      #expect(tableNames.contains("tag"))
      #expect(tableNames.contains("podcastTag"))

      let tagCols = try Row.fetchAll(db, sql: "PRAGMA table_info('tag')")
      let tagColNames = Set(tagCols.compactMap { $0["name"] as? String })
      #expect(tagColNames == Set(["id", "name", "creationDate"]))

      let podcastTagCols = try Row.fetchAll(db, sql: "PRAGMA table_info('podcastTag')")
      let podcastTagColNames = Set(podcastTagCols.compactMap { $0["name"] as? String })
      #expect(podcastTagColNames == Set(["podcastId", "tagId"]))

      let indexes = try Row.fetchAll(
        db,
        sql: "SELECT name FROM sqlite_master WHERE type = 'index'"
      )
      let indexNames = Set(indexes.compactMap { $0["name"] as? String })
      #expect(indexNames.contains("podcastTag_on_podcastId"))
      #expect(indexNames.contains("podcastTag_on_tagId"))
    }

    let (podcastID, tagID) = try await appDB.db.write { db in
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
          INSERT INTO tag (name)
          VALUES (?)
          """,
        arguments: ["Tech"]
      )
      let tagID = db.lastInsertedRowID

      return (podcastID, tagID)
    }

    await #expect(throws: DatabaseError.self) {
      try await self.appDB.db.write { db in
        try db.execute(
          sql: """
            INSERT INTO tag (name)
            VALUES (?)
            """,
          arguments: ["tech"]
        )
      }
    }

    try await appDB.db.read { db in
      let tagCount = try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM tag")
      #expect(tagCount == 1)
    }

    try await appDB.db.write { db in
      try db.execute(
        sql: """
          INSERT INTO podcastTag (podcastId, tagId)
          VALUES (?, ?)
          """,
        arguments: [podcastID, tagID]
      )
    }

    await #expect(throws: DatabaseError.self) {
      try await self.appDB.db.write { db in
        try db.execute(
          sql: """
            INSERT INTO podcastTag (podcastId, tagId)
            VALUES (?, ?)
            """,
          arguments: [podcastID, tagID]
        )
      }
    }

    try await appDB.db.read { db in
      let mappingCount = try Int.fetchOne(
        db,
        sql: """
          SELECT COUNT(*)
          FROM podcastTag
          WHERE podcastId = ? AND tagId = ?
          """,
        arguments: [podcastID, tagID]
      )
      #expect(mappingCount == 1)
    }

    try await appDB.db.write { db in
      try db.execute(
        sql: "DELETE FROM tag WHERE id = ?",
        arguments: [tagID]
      )
    }

    try await appDB.db.read { db in
      let remainingMappings = try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM podcastTag")
      #expect(remainingMappings == 0)
    }
  }
}
