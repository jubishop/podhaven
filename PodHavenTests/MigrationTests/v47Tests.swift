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
      }
    }
  }

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
  }
}
