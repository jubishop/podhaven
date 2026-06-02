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

<<<<<<< HEAD
  private func insertPodcast(feedURL: String, cadence: String?) -> @Sendable (Database) throws -> Void
  {
    { db in
      try db.execute(
        sql: """
          INSERT INTO podcast (feedURL, title, image, description, freshnessCadence)
          VALUES (?, ?, ?, ?, ?)
          """,
        arguments: [feedURL, "T", "img", "desc", cadence]
      )
    }
  }

  @Test("v46 rejects the new fine-grained cadence values")
  func v46RejectsNewCadences() async throws {
    try migrator.migrate(appDB.unsafeTestDB, upTo: "v46")
    for cadence in ["hourly", "twiceDaily", "twiceWeekly"] {
      let insert = insertPodcast(feedURL: "https://example.com/\(cadence).xml", cadence: cadence)
      await #expect(throws: DatabaseError.self) {
        try await self.appDB.unsafeTestDB.write(insert)
=======
  @Test("v47 adds nullable autoQueueLimit column to podcast")
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
      #expect(!colNames.contains("autoQueueLimit"))
    }

    try migrator.migrate(appDB.unsafeTestDB, upTo: "v47")

    try await appDB.unsafeTestDB.read { db in
      let cols = try Row.fetchAll(db, sql: "PRAGMA table_info('podcast')")
      let col = try #require(cols.first { $0["name"] as? String == "autoQueueLimit" })
      #expect(col["type"] as? String == "INTEGER")
      #expect((col["notnull"] as? Int64 ?? 0) == 0)
    }

    // Existing rows get NULL (limit unset).
    try await appDB.unsafeTestDB.read { db in
      let row = try #require(
        try Row.fetchOne(
          db,
          sql: "SELECT autoQueueLimit FROM podcast WHERE id = ?",
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
          INSERT INTO podcast (feedURL, title, image, description, autoQueueLimit)
          VALUES (?, ?, ?, ?, ?)
          """,
        arguments: ["https://example.com/min.xml", "Min", "img", "desc", 1]
      )
      try db.execute(
        sql: """
          INSERT INTO podcast (feedURL, title, image, description, autoQueueLimit)
          VALUES (?, ?, ?, ?, ?)
          """,
        arguments: ["https://example.com/max.xml", "Max", "img", "desc", 5]
      )
      try db.execute(
        sql: """
          INSERT INTO podcast (feedURL, title, image, description, autoQueueLimit)
          VALUES (?, ?, ?, ?, ?)
          """,
        arguments: ["https://example.com/null.xml", "Null", "img", "desc", nil]
      )
    }

    // Extract Sendable tuples inside the read closure — Row is not Sendable.
    let rows: [(feedURL: String, limit: Int64?)] = try await appDB.unsafeTestDB.read { db in
      try Row.fetchAll(
        db,
        sql: "SELECT feedURL, autoQueueLimit FROM podcast ORDER BY feedURL"
      )
      .map { row in
        (feedURL: row["feedURL"] as String, limit: row["autoQueueLimit"] as Int64?)
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
              INSERT INTO podcast (feedURL, title, image, description, autoQueueLimit)
              VALUES (?, ?, ?, ?, ?)
              """,
            arguments: ["https://example.com/\(invalid).xml", "Bad", "img", "desc", invalid]
          )
        }
>>>>>>> origin/main
      }
    }
  }

<<<<<<< HEAD
  @Test("v47 accepts the new fine-grained cadence values alongside the old ones and NULL")
  func v47AcceptsAllCadences() async throws {
    try migrator.migrate(appDB.unsafeTestDB, upTo: "v47")

    let valid = [
      "hourly", "twiceDaily", "daily", "twiceWeekly", "weekly", "monthly", "evergreen",
    ]
    try await appDB.unsafeTestDB.write { db in
      for cadence in valid {
        try db.execute(
          sql: """
            INSERT INTO podcast (feedURL, title, image, description, freshnessCadence)
            VALUES (?, ?, ?, ?, ?)
            """,
          arguments: ["https://example.com/\(cadence).xml", "T", "img", "desc", cadence]
        )
      }
      // NULL (auto) stays valid.
      try db.execute(
        sql: "INSERT INTO podcast (feedURL, title, image, description) VALUES (?, ?, ?, ?)",
        arguments: ["https://example.com/auto.xml", "Auto", "img", "desc"]
      )
    }

    let rows: [(feedURL: String, cadence: String?)] = try await appDB.unsafeTestDB.read { db in
      try Row.fetchAll(db, sql: "SELECT feedURL, freshnessCadence FROM podcast")
        .map { (feedURL: $0["feedURL"] as String, cadence: $0["freshnessCadence"] as String?) }
    }
    #expect(rows.count == valid.count + 1)
    for cadence in valid {
      let url = "https://example.com/\(cadence).xml"
      let row = try #require(rows.first { $0.feedURL == url })
      #expect(row.cadence == cadence)
    }
    let autoRow = try #require(rows.first { $0.feedURL == "https://example.com/auto.xml" })
    #expect(autoRow.cadence == nil)
  }

  @Test("v47 still rejects unknown cadence strings")
  func v47RejectsUnknownCadence() async throws {
    try migrator.migrate(appDB.unsafeTestDB, upTo: "v47")
    let insert = insertPodcast(feedURL: "https://example.com/bogus.xml", cadence: "yearly")
    await #expect(throws: DatabaseError.self) {
      try await self.appDB.unsafeTestDB.write(insert)
    }
  }

  @Test("v47 preserves existing podcast rows and their cadence")
  func v47PreservesRows() async throws {
    try migrator.migrate(appDB.unsafeTestDB, upTo: "v46")
    try await appDB.unsafeTestDB.write { db in
      try db.execute(
        sql: """
          INSERT INTO podcast (feedURL, title, image, description, freshnessCadence)
          VALUES (?, ?, ?, ?, ?)
          """,
        arguments: ["https://example.com/weekly.xml", "Weekly", "img", "desc", "weekly"]
      )
      try db.execute(
        sql: "INSERT INTO podcast (feedURL, title, image, description) VALUES (?, ?, ?, ?)",
        arguments: ["https://example.com/auto.xml", "Auto", "img", "desc"]
      )
    }

    try migrator.migrate(appDB.unsafeTestDB, upTo: "v47")

    let rows: [(feedURL: String, cadence: String?)] = try await appDB.unsafeTestDB.read { db in
      try Row.fetchAll(db, sql: "SELECT feedURL, freshnessCadence FROM podcast ORDER BY feedURL")
        .map { (feedURL: $0["feedURL"] as String, cadence: $0["freshnessCadence"] as String?) }
    }
    #expect(rows.count == 2)
    let weekly = try #require(rows.first { $0.feedURL.contains("weekly") })
    #expect(weekly.cadence == "weekly")
    let auto = try #require(rows.first { $0.feedURL.contains("auto") })
    #expect(auto.cadence == nil)
=======
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
        sql: "UPDATE podcast SET autoQueueLimit = ? WHERE id = ?",
        arguments: [3, id]
      )
    }
    let setValue = try await appDB.unsafeTestDB.read { db in
      try Int.fetchOne(
        db,
        sql: "SELECT autoQueueLimit FROM podcast WHERE id = ?",
        arguments: [id]
      )
    }
    #expect(setValue == 3)

    try await appDB.unsafeTestDB.write { db in
      try db.execute(
        sql: "UPDATE podcast SET autoQueueLimit = NULL WHERE id = ?",
        arguments: [id]
      )
    }
    let cleared: Int64? = try await appDB.unsafeTestDB.read { db in
      try Int64.fetchOne(
        db,
        sql: "SELECT autoQueueLimit FROM podcast WHERE id = ?",
        arguments: [id]
      )
    }
    #expect(cleared == nil)

    await #expect(throws: DatabaseError.self) {
      try await self.appDB.unsafeTestDB.write { db in
        try db.execute(
          sql: "UPDATE podcast SET autoQueueLimit = ? WHERE id = ?",
          arguments: [6, id]
        )
      }
    }
>>>>>>> origin/main
  }
}
