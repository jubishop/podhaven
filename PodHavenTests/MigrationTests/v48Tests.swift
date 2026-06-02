// Copyright Justin Bishop, 2026

import Foundation
import GRDB
import Testing

@testable import PodHaven

@Suite("of v48 migration tests", .container)
class V48MigrationTests {
  private let appDB = AppDB.inMemory(migrate: false)
  private let migrator: DatabaseMigrator

  init() async throws {
    self.migrator = Schema.makeMigrator()
  }

  private func insertPodcast(feedURL: String, cadence: String?) -> @Sendable (Database) throws ->
    Void
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

  @Test("v47 still rejects the new fine-grained cadence values")
  func v47RejectsNewCadences() async throws {
    try migrator.migrate(appDB.unsafeTestDB, upTo: "v47")
    for cadence in ["hourly", "twiceDaily", "twiceWeekly"] {
      let insert = insertPodcast(feedURL: "https://example.com/\(cadence).xml", cadence: cadence)
      await #expect(throws: DatabaseError.self) {
        try await self.appDB.unsafeTestDB.write(insert)
      }
    }
  }

  @Test("v48 accepts the new fine-grained cadence values alongside the old ones and NULL")
  func v48AcceptsAllCadences() async throws {
    try migrator.migrate(appDB.unsafeTestDB, upTo: "v48")

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

  @Test("v48 still rejects unknown cadence strings")
  func v48RejectsUnknownCadence() async throws {
    try migrator.migrate(appDB.unsafeTestDB, upTo: "v48")
    let insert = insertPodcast(feedURL: "https://example.com/bogus.xml", cadence: "yearly")
    await #expect(throws: DatabaseError.self) {
      try await self.appDB.unsafeTestDB.write(insert)
    }
  }

  @Test("v48 preserves existing podcast rows, their cadence, and autoQueueLimit")
  func v48PreservesRows() async throws {
    try migrator.migrate(appDB.unsafeTestDB, upTo: "v47")
    try await appDB.unsafeTestDB.write { db in
      // Carries both the v39 freshnessCadence and the v47 autoQueueLimit
      // columns — the v48 table rebuild must keep both intact.
      try db.execute(
        sql: """
          INSERT INTO podcast (feedURL, title, image, description, freshnessCadence, autoQueueLimit)
          VALUES (?, ?, ?, ?, ?, ?)
          """,
        arguments: ["https://example.com/weekly.xml", "Weekly", "img", "desc", "weekly", 3]
      )
      try db.execute(
        sql: "INSERT INTO podcast (feedURL, title, image, description) VALUES (?, ?, ?, ?)",
        arguments: ["https://example.com/auto.xml", "Auto", "img", "desc"]
      )
    }

    try migrator.migrate(appDB.unsafeTestDB, upTo: "v48")

    let rows: [(feedURL: String, cadence: String?, limit: Int64?)] =
      try await appDB.unsafeTestDB.read { db in
        try Row.fetchAll(
          db,
          sql: "SELECT feedURL, freshnessCadence, autoQueueLimit FROM podcast ORDER BY feedURL"
        )
        .map {
          (
            feedURL: $0["feedURL"] as String,
            cadence: $0["freshnessCadence"] as String?,
            limit: $0["autoQueueLimit"] as Int64?
          )
        }
      }
    #expect(rows.count == 2)
    let weekly = try #require(rows.first { $0.feedURL.contains("weekly") })
    #expect(weekly.cadence == "weekly")
    #expect(weekly.limit == 3)
    let auto = try #require(rows.first { $0.feedURL.contains("auto") })
    #expect(auto.cadence == nil)
    #expect(auto.limit == nil)
  }
}
