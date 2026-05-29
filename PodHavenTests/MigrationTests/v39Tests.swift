// Copyright Justin Bishop, 2026

import Foundation
import GRDB
import Testing

@testable import PodHaven

@Suite("of v39 migration tests", .container)
class V39MigrationTests {
  private let appDB = AppDB.inMemory(migrate: false)
  private let migrator: DatabaseMigrator

  init() async throws {
    self.migrator = Schema.makeMigrator()
  }

  @Test("v39 swaps freshnessHalfLifeDays for nullable freshnessCadence and leaves rows nil")
  func columnsSwapped() async throws {
    try migrator.migrate(appDB.unsafeTestDB, upTo: "v38")

    let existingID = try await appDB.unsafeTestDB.write { db in
      try db.execute(
        sql: """
          INSERT INTO podcast (feedURL, title, image, description, freshnessHalfLifeDays)
          VALUES (?, ?, ?, ?, ?)
          """,
        arguments: [
          "https://example.com/feed.xml",
          "Existing Podcast",
          "https://example.com/image.jpg",
          "Existing description",
          365,
        ]
      )
      return db.lastInsertedRowID
    }

    try await appDB.unsafeTestDB.read { db in
      let cols = try Row.fetchAll(db, sql: "PRAGMA table_info('podcast')")
      let names = Set(cols.compactMap { $0["name"] as? String })
      #expect(names.contains("freshnessHalfLifeDays"))
      #expect(!names.contains("freshnessCadence"))
    }

    try migrator.migrate(appDB.unsafeTestDB, upTo: "v39")

    try await appDB.unsafeTestDB.read { db in
      let cols = try Row.fetchAll(db, sql: "PRAGMA table_info('podcast')")
      let names = Set(cols.compactMap { $0["name"] as? String })
      #expect(!names.contains("freshnessHalfLifeDays"))
      let cadenceCol = try #require(cols.first { $0["name"] as? String == "freshnessCadence" })
      #expect(cadenceCol["type"] as? String == "TEXT")
      // Column is nullable — auto resolution happens at scoring time, not as
      // a schema-level default.
      #expect((cadenceCol["notnull"] as? Int64 ?? 0) == 0)
    }

    let existingCadence = try await appDB.unsafeTestDB.read { db in
      try String.fetchOne(
        db,
        sql: "SELECT freshnessCadence FROM podcast WHERE id = ?",
        arguments: [existingID]
      )
    }
    #expect(existingCadence == nil)
  }

  @Test("v39 accepts every cadence value plus NULL")
  func acceptsValidValues() async throws {
    try migrator.migrate(appDB.unsafeTestDB, upTo: "v39")

    let cadences: [String?] = ["daily", "weekly", "monthly", "evergreen", nil]
    try await appDB.unsafeTestDB.write { db in
      for (index, cadence) in cadences.enumerated() {
        try db.execute(
          sql: """
            INSERT INTO podcast (feedURL, title, image, description, freshnessCadence)
            VALUES (?, ?, ?, ?, ?)
            """,
          arguments: [
            "https://example.com/feed-\(index).xml",
            "row-\(index)",
            "img",
            "desc",
            cadence,
          ]
        )
      }
    }

    let storedCadences: [String?] = try await appDB.unsafeTestDB.read { db in
      try Row.fetchAll(db, sql: "SELECT freshnessCadence FROM podcast ORDER BY id")
        .map { $0["freshnessCadence"] as String? }
    }
    #expect(storedCadences == cadences)
  }

  @Test("v39 rejects unknown cadence values")
  func rejectsUnknownCadence() async throws {
    try migrator.migrate(appDB.unsafeTestDB, upTo: "v39")

    await #expect(throws: DatabaseError.self) {
      try await self.appDB.unsafeTestDB.write { db in
        try db.execute(
          sql: """
            INSERT INTO podcast (feedURL, title, image, description, freshnessCadence)
            VALUES (?, ?, ?, ?, ?)
            """,
          arguments: [
            "https://example.com/bogus.xml", "Bogus", "img", "desc", "biweekly",
          ]
        )
      }
    }
  }

  @Test("v39 leaves cadence NULL when column is omitted from INSERT")
  func defaultsToNullOnInsert() async throws {
    try migrator.migrate(appDB.unsafeTestDB, upTo: "v39")

    let id = try await appDB.unsafeTestDB.write { db in
      try db.execute(
        sql: """
          INSERT INTO podcast (feedURL, title, image, description)
          VALUES (?, ?, ?, ?)
          """,
        arguments: [
          "https://example.com/new.xml", "New", "img", "desc",
        ]
      )
      return db.lastInsertedRowID
    }

    let cadence = try await appDB.unsafeTestDB.read { db in
      try String.fetchOne(
        db,
        sql: "SELECT freshnessCadence FROM podcast WHERE id = ?",
        arguments: [id]
      )
    }
    #expect(cadence == nil)
  }
}
