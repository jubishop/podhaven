// Copyright Justin Bishop, 2026

import Foundation
import GRDB
import Testing

@testable import PodHaven

@Suite("of v38 migration tests", .container)
class V38MigrationTests {
  private let appDB = AppDB.inMemory(migrate: false)
  private let migrator: DatabaseMigrator

  init() async throws {
    self.migrator = Schema.makeMigrator()
  }

  @Test("v38 adds nullable freshnessHalfLifeDays column to podcast")
  func columnAdded() async throws {
    try migrator.migrate(appDB.db, upTo: "v37")

    let existingID = try await appDB.db.write { db in
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

    try await appDB.db.read { db in
      let cols = try Row.fetchAll(db, sql: "PRAGMA table_info('podcast')")
      let colNames = Set(cols.compactMap { $0["name"] as? String })
      #expect(!colNames.contains("freshnessHalfLifeDays"))
    }

    try migrator.migrate(appDB.db, upTo: "v38")

    try await appDB.db.read { db in
      let cols = try Row.fetchAll(db, sql: "PRAGMA table_info('podcast')")
      let col = try #require(cols.first { $0["name"] as? String == "freshnessHalfLifeDays" })
      #expect(col["type"] as? String == "INTEGER")
      #expect((col["notnull"] as? Int64 ?? 0) == 0)
    }

    // Existing rows get NULL (no override).
    try await appDB.db.read { db in
      let row = try #require(
        try Row.fetchOne(
          db,
          sql: "SELECT freshnessHalfLifeDays FROM podcast WHERE id = ?",
          arguments: [existingID]
        )
      )
      #expect(row.hasNull(atIndex: 0))
    }
  }

  @Test("v38 accepts valid values and NULL")
  func acceptsValidValues() async throws {
    try migrator.migrate(appDB.db, upTo: "v38")

    try await appDB.db.write { db in
      try db.execute(
        sql: """
          INSERT INTO podcast (feedURL, title, image, description, freshnessHalfLifeDays)
          VALUES (?, ?, ?, ?, ?)
          """,
        arguments: [
          "https://example.com/news.xml", "News", "img", "desc", 30,
        ]
      )
      try db.execute(
        sql: """
          INSERT INTO podcast (feedURL, title, image, description, freshnessHalfLifeDays)
          VALUES (?, ?, ?, ?, ?)
          """,
        arguments: [
          "https://example.com/evergreen.xml", "Evergreen", "img", "desc", 730,
        ]
      )
      try db.execute(
        sql: """
          INSERT INTO podcast (feedURL, title, image, description, freshnessHalfLifeDays)
          VALUES (?, ?, ?, ?, ?)
          """,
        arguments: [
          "https://example.com/null.xml", "Null", "img", "desc", nil,
        ]
      )
    }

    // Extract Sendable tuples inside the read closure — Row is not Sendable.
    let rows: [(feedURL: String, halfLife: Int64?)] = try await appDB.db.read { db in
      try Row.fetchAll(
        db,
        sql: "SELECT feedURL, freshnessHalfLifeDays FROM podcast ORDER BY feedURL"
      )
      .map { row in
        (
          feedURL: row["feedURL"] as String,
          halfLife: row["freshnessHalfLifeDays"] as Int64?
        )
      }
    }
    #expect(rows.count == 3)
    let news = try #require(rows.first { $0.feedURL.contains("news") })
    #expect(news.halfLife == 30)
    let evergreen = try #require(rows.first { $0.feedURL.contains("evergreen") })
    #expect(evergreen.halfLife == 730)
    let nullRow = try #require(rows.first { $0.feedURL.contains("null") })
    #expect(nullRow.halfLife == nil)
  }

  @Test("v38 rejects values below 1")
  func rejectsBelowMinimum() async throws {
    try migrator.migrate(appDB.db, upTo: "v38")

    await #expect(throws: DatabaseError.self) {
      try await self.appDB.db.write { db in
        try db.execute(
          sql: """
            INSERT INTO podcast (feedURL, title, image, description, freshnessHalfLifeDays)
            VALUES (?, ?, ?, ?, ?)
            """,
          arguments: [
            "https://example.com/zero.xml", "Zero", "img", "desc", 0,
          ]
        )
      }
    }

    await #expect(throws: DatabaseError.self) {
      try await self.appDB.db.write { db in
        try db.execute(
          sql: """
            INSERT INTO podcast (feedURL, title, image, description, freshnessHalfLifeDays)
            VALUES (?, ?, ?, ?, ?)
            """,
          arguments: [
            "https://example.com/negative.xml", "Neg", "img", "desc", -5,
          ]
        )
      }
    }
  }

  @Test("v38 allows UPDATE to a valid value and to NULL (clear)")
  func updateAllowed() async throws {
    try migrator.migrate(appDB.db, upTo: "v38")

    let id = try await appDB.db.write { db in
      try db.execute(
        sql: """
          INSERT INTO podcast (feedURL, title, image, description)
          VALUES (?, ?, ?, ?)
          """,
        arguments: [
          "https://example.com/feed.xml", "T", "img", "desc",
        ]
      )
      return db.lastInsertedRowID
    }

    try await appDB.db.write { db in
      try db.execute(
        sql: "UPDATE podcast SET freshnessHalfLifeDays = ? WHERE id = ?",
        arguments: [90, id]
      )
    }
    let setValue = try await appDB.db.read { db in
      try Int.fetchOne(
        db,
        sql: "SELECT freshnessHalfLifeDays FROM podcast WHERE id = ?",
        arguments: [id]
      )
    }
    #expect(setValue == 90)

    try await appDB.db.write { db in
      try db.execute(
        sql: "UPDATE podcast SET freshnessHalfLifeDays = NULL WHERE id = ?",
        arguments: [id]
      )
    }
    let clearedHalfLife: Int64? = try await appDB.db.read { db in
      try Int64.fetchOne(
        db,
        sql: "SELECT freshnessHalfLifeDays FROM podcast WHERE id = ?",
        arguments: [id]
      )
    }
    #expect(clearedHalfLife == nil)

    await #expect(throws: DatabaseError.self) {
      try await self.appDB.db.write { db in
        try db.execute(
          sql: "UPDATE podcast SET freshnessHalfLifeDays = ? WHERE id = ?",
          arguments: [0, id]
        )
      }
    }
  }
}
