// Copyright Justin Bishop, 2026

import Foundation
import GRDB
import Testing

@testable import PodHaven

@Suite("of v49 migration tests", .container)
class V49MigrationTests {
  private let appDB = AppDB.inMemory(migrate: false)
  private let migrator: DatabaseMigrator

  init() async throws {
    self.migrator = Schema.makeMigrator()
  }

  private func insertPodcast(feedURL: String, cadence: String?)
    -> @Sendable (Database) throws ->
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

  private func podcastFTSMatches(_ term: String) async throws -> [Int64] {
    try await appDB.unsafeTestDB.read { db in
      try Int64.fetchAll(
        db,
        sql: "SELECT rowid FROM podcast_fts WHERE podcast_fts MATCH ? ORDER BY rowid",
        arguments: [term]
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

  @Test("v49 accepts the new fine-grained cadence values alongside the old ones and NULL")
  func v49AcceptsAllCadences() async throws {
    try migrator.migrate(appDB.unsafeTestDB, upTo: "v49")

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

  @Test("v49 still rejects unknown cadence strings")
  func v49RejectsUnknownCadence() async throws {
    try migrator.migrate(appDB.unsafeTestDB, upTo: "v49")
    let insert = insertPodcast(feedURL: "https://example.com/bogus.xml", cadence: "yearly")
    await #expect(throws: DatabaseError.self) {
      try await self.appDB.unsafeTestDB.write(insert)
    }
  }

  @Test("v49 preserves existing podcast rows, their cadence, and autoQueueLimit")
  func v49PreservesRows() async throws {
    try migrator.migrate(appDB.unsafeTestDB, upTo: "v47")
    try await appDB.unsafeTestDB.write { db in
      // Carries both the v39 freshnessCadence and the v47 autoQueueLimit
      // columns — the v49 table rebuild must keep both intact.
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

    try migrator.migrate(appDB.unsafeTestDB, upTo: "v49")

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

  // The v49 podcast rebuild drops the FTS5 sync triggers the v48 migration
  // installed, orphaning podcast_fts, so v49 recreates the mirror. Prove it
  // survives: a pre-existing row is re-backfilled and post-migration writes
  // still propagate through the freshly installed triggers.
  @Test("v49 keeps podcast_fts in sync after rebuilding the podcast table")
  func v49RebuildsPodcastFTS() async throws {
    try migrator.migrate(appDB.unsafeTestDB, upTo: "v48")
    let podcastId = try await appDB.unsafeTestDB.write { db -> Int64 in
      try db.execute(
        sql: """
          INSERT INTO podcast (feedURL, title, image, description)
          VALUES (?, ?, 'img', ?)
          """,
        arguments: ["https://example.com/astro.xml", "Astronomy Weekly", "Stars and galaxies"]
      )
      return db.lastInsertedRowID
    }

    try migrator.migrate(appDB.unsafeTestDB, upTo: "v49")

    // The pre-existing row is re-backfilled into the recreated mirror.
    #expect(try await podcastFTSMatches("astronomy") == [podcastId])

    // Freshly installed triggers keep the mirror current after the rebuild.
    try await appDB.unsafeTestDB.write { db in
      try db.execute(
        sql: "UPDATE podcast SET title = 'Geology Weekly' WHERE id = ?",
        arguments: [podcastId]
      )
    }
    #expect(try await podcastFTSMatches("astronomy").isEmpty)
    #expect(try await podcastFTSMatches("geology") == [podcastId])
  }
}
