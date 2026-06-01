// Copyright Justin Bishop, 2026

import Foundation
import GRDB
import Testing

@testable import PodHaven

@Suite("of v47 migration tests", .container)
class V47MigrationTests {
  private let appDB = AppDB.inMemory(migrate: false)
  private let migrator: DatabaseMigrator

  init() async throws {
    self.migrator = Schema.makeMigrator()
  }

  @Test("v47 adds nullable queueLimit column to podcast")
  func columnAdded() async throws {
    try migrator.migrate(appDB.unsafeTestDB, upTo: "v46")

    let existingID = try await appDB.unsafeTestDB.write { db in
      try db.execute(
        sql: """
          INSERT INTO podcast (feedURL, title, image, description)
          VALUES (?, ?, ?, ?)
          """,
        arguments: [
          "https://example.com/feed.xml",
          "Existing Podcast",
          "https://example.com/image.jpg",
          "Existing description",
        ]
      )
      return db.lastInsertedRowID
    }

    try await appDB.unsafeTestDB.read { db in
      let cols = try Row.fetchAll(db, sql: "PRAGMA table_info('podcast')")
      let colNames = Set(cols.compactMap { $0["name"] as? String })
      #expect(!colNames.contains("queueLimit"))
    }

    try migrator.migrate(appDB.unsafeTestDB, upTo: "v47")

    try await appDB.unsafeTestDB.read { db in
      let cols = try Row.fetchAll(db, sql: "PRAGMA table_info('podcast')")
      let col = try #require(cols.first { $0["name"] as? String == "queueLimit" })
      #expect(col["type"] as? String == "INTEGER")
      #expect((col["notnull"] as? Int64 ?? 0) == 0)
    }

    // Existing rows get NULL (limit unset).
    try await appDB.unsafeTestDB.read { db in
      let row = try #require(
        try Row.fetchOne(
          db,
          sql: "SELECT queueLimit FROM podcast WHERE id = ?",
          arguments: [existingID]
        )
      )
      #expect(row.hasNull(atIndex: 0))
    }
  }

  @Test("v47 accepts the boundary values and NULL")
  func acceptsValidValues() async throws {
    try migrator.migrate(appDB.unsafeTestDB, upTo: "v47")

    try await appDB.unsafeTestDB.write { db in
      try db.execute(
        sql: """
          INSERT INTO podcast (feedURL, title, image, description, queueLimit)
          VALUES (?, ?, ?, ?, ?)
          """,
        arguments: ["https://example.com/min.xml", "Min", "img", "desc", 1]
      )
      try db.execute(
        sql: """
          INSERT INTO podcast (feedURL, title, image, description, queueLimit)
          VALUES (?, ?, ?, ?, ?)
          """,
        arguments: ["https://example.com/max.xml", "Max", "img", "desc", 5]
      )
      try db.execute(
        sql: """
          INSERT INTO podcast (feedURL, title, image, description, queueLimit)
          VALUES (?, ?, ?, ?, ?)
          """,
        arguments: ["https://example.com/null.xml", "Null", "img", "desc", nil]
      )
    }

    // Extract Sendable tuples inside the read closure — Row is not Sendable.
    let rows: [(feedURL: String, limit: Int64?)] = try await appDB.unsafeTestDB.read { db in
      try Row.fetchAll(
        db,
        sql: "SELECT feedURL, queueLimit FROM podcast ORDER BY feedURL"
      )
      .map { row in
        (feedURL: row["feedURL"] as String, limit: row["queueLimit"] as Int64?)
      }
    }
    #expect(rows.count == 3)
    #expect(try #require(rows.first { $0.feedURL.contains("min") }).limit == 1)
    #expect(try #require(rows.first { $0.feedURL.contains("max") }).limit == 5)
    #expect(try #require(rows.first { $0.feedURL.contains("null") }).limit == nil)
  }

  @Test("v47 rejects values outside 1...5")
  func rejectsOutOfRange() async throws {
    try migrator.migrate(appDB.unsafeTestDB, upTo: "v47")

    for invalid in [0, 6, -1] {
      await #expect(throws: DatabaseError.self) {
        try await self.appDB.unsafeTestDB.write { db in
          try db.execute(
            sql: """
              INSERT INTO podcast (feedURL, title, image, description, queueLimit)
              VALUES (?, ?, ?, ?, ?)
              """,
            arguments: ["https://example.com/\(invalid).xml", "Bad", "img", "desc", invalid]
          )
        }
      }
    }
  }

  @Test("v47 allows UPDATE to a valid value and to NULL (clear)")
  func updateAllowed() async throws {
    try migrator.migrate(appDB.unsafeTestDB, upTo: "v47")

    let id = try await appDB.unsafeTestDB.write { db in
      try db.execute(
        sql: """
          INSERT INTO podcast (feedURL, title, image, description)
          VALUES (?, ?, ?, ?)
          """,
        arguments: ["https://example.com/feed.xml", "T", "img", "desc"]
      )
      return db.lastInsertedRowID
    }

    try await appDB.unsafeTestDB.write { db in
      try db.execute(
        sql: "UPDATE podcast SET queueLimit = ? WHERE id = ?",
        arguments: [3, id]
      )
    }
    let setValue = try await appDB.unsafeTestDB.read { db in
      try Int.fetchOne(
        db,
        sql: "SELECT queueLimit FROM podcast WHERE id = ?",
        arguments: [id]
      )
    }
    #expect(setValue == 3)

    try await appDB.unsafeTestDB.write { db in
      try db.execute(
        sql: "UPDATE podcast SET queueLimit = NULL WHERE id = ?",
        arguments: [id]
      )
    }
    let cleared: Int64? = try await appDB.unsafeTestDB.read { db in
      try Int64.fetchOne(
        db,
        sql: "SELECT queueLimit FROM podcast WHERE id = ?",
        arguments: [id]
      )
    }
    #expect(cleared == nil)

    await #expect(throws: DatabaseError.self) {
      try await self.appDB.unsafeTestDB.write { db in
        try db.execute(
          sql: "UPDATE podcast SET queueLimit = ? WHERE id = ?",
          arguments: [6, id]
        )
      }
    }
  }
}
