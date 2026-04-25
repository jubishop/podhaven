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

  @Test("v39 swaps freshnessHalfLifeDays for freshnessCadence with weekly default")
  func columnsSwapped() async throws {
    try migrator.migrate(appDB.db, upTo: "v38")

    let existingID = try await appDB.db.write { db in
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

    try await appDB.db.read { db in
      let cols = try Row.fetchAll(db, sql: "PRAGMA table_info('podcast')")
      let names = Set(cols.compactMap { $0["name"] as? String })
      #expect(names.contains("freshnessHalfLifeDays"))
      #expect(!names.contains("freshnessCadence"))
    }

    try migrator.migrate(appDB.db, upTo: "v39")

    try await appDB.db.read { db in
      let cols = try Row.fetchAll(db, sql: "PRAGMA table_info('podcast')")
      let names = Set(cols.compactMap { $0["name"] as? String })
      #expect(!names.contains("freshnessHalfLifeDays"))
      let cadenceCol = try #require(cols.first { $0["name"] as? String == "freshnessCadence" })
      #expect(cadenceCol["type"] as? String == "TEXT")
      #expect((cadenceCol["notnull"] as? Int64 ?? 0) == 1)
    }

    let existingCadence = try await appDB.db.read { db in
      try String.fetchOne(
        db,
        sql: "SELECT freshnessCadence FROM podcast WHERE id = ?",
        arguments: [existingID]
      )
    }
    #expect(existingCadence == "weekly")
  }

  @Test("v39 accepts every cadence value")
  func acceptsValidValues() async throws {
    try migrator.migrate(appDB.db, upTo: "v39")

    let cadences = ["daily", "weekly", "monthly", "evergreen"]
    try await appDB.db.write { db in
      for (index, cadence) in cadences.enumerated() {
        try db.execute(
          sql: """
            INSERT INTO podcast (feedURL, title, image, description, freshnessCadence)
            VALUES (?, ?, ?, ?, ?)
            """,
          arguments: [
            "https://example.com/feed-\(index).xml",
            cadence.capitalized,
            "img",
            "desc",
            cadence,
          ]
        )
      }
    }

    let storedCadences: [String] = try await appDB.db.read { db in
      try String.fetchAll(
        db,
        sql: "SELECT freshnessCadence FROM podcast ORDER BY id"
      )
    }
    #expect(storedCadences == cadences)
  }

  @Test("v39 rejects unknown cadence values")
  func rejectsUnknownCadence() async throws {
    try migrator.migrate(appDB.db, upTo: "v39")

    await #expect(throws: DatabaseError.self) {
      try await self.appDB.db.write { db in
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

  @Test("v39 rejects NULL freshnessCadence")
  func rejectsNullCadence() async throws {
    try migrator.migrate(appDB.db, upTo: "v39")

    await #expect(throws: DatabaseError.self) {
      try await self.appDB.db.write { db in
        try db.execute(
          sql: """
            INSERT INTO podcast (feedURL, title, image, description, freshnessCadence)
            VALUES (?, ?, ?, ?, ?)
            """,
          arguments: [
            "https://example.com/null.xml", "Null", "img", "desc", nil,
          ]
        )
      }
    }
  }

  @Test("v39 default kicks in when column is omitted from INSERT")
  func defaultAppliesOnInsert() async throws {
    try migrator.migrate(appDB.db, upTo: "v39")

    let id = try await appDB.db.write { db in
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

    let cadence = try await appDB.db.read { db in
      try String.fetchOne(
        db,
        sql: "SELECT freshnessCadence FROM podcast WHERE id = ?",
        arguments: [id]
      )
    }
    #expect(cadence == "weekly")
  }

  @Test("v39 backfills cadence based on each podcast's episode pubDates")
  func backfillInfersCadence() async throws {
    try migrator.migrate(appDB.db, upTo: "v38")

    // Three podcasts: one with daily-ish gaps, one with weekly gaps, one
    // dormant for over a year. After v39 runs, each should land on the
    // expected cadence bucket without us having to set anything by hand.
    let now = Date()
    let dailyID = try await insertPodcast(
      feedURL: "https://example.com/daily.xml",
      pubDateOffsetsDays: [0, 1, 2, 3, 4],
      now: now
    )
    let weeklyID = try await insertPodcast(
      feedURL: "https://example.com/weekly.xml",
      pubDateOffsetsDays: [0, 7, 14, 21, 28],
      now: now
    )
    let dormantID = try await insertPodcast(
      feedURL: "https://example.com/dormant.xml",
      pubDateOffsetsDays: [400, 407, 414, 421],
      now: now
    )
    let sparseID = try await insertPodcast(
      feedURL: "https://example.com/sparse.xml",
      pubDateOffsetsDays: [0],
      now: now
    )

    try migrator.migrate(appDB.db, upTo: "v39")

    let cadences: [Int64: String] = try await appDB.db.read { db in
      let rows = try Row.fetchAll(db, sql: "SELECT id, freshnessCadence FROM podcast")
      var dict = [Int64: String](capacity: rows.count)
      for row in rows {
        dict[row["id"] as Int64] = row["freshnessCadence"] as String
      }
      return dict
    }
    #expect(cadences[dailyID] == "daily")
    #expect(cadences[weeklyID] == "weekly")
    #expect(cadences[dormantID] == "evergreen")
    #expect(cadences[sparseID] == "weekly")
  }

  // MARK: - Helpers

  private func insertPodcast(
    feedURL: String,
    pubDateOffsetsDays: [Double],
    now: Date
  ) async throws -> Int64 {
    try await appDB.db.write { db in
      try db.execute(
        sql: """
          INSERT INTO podcast (feedURL, title, image, description)
          VALUES (?, ?, ?, ?)
          """,
        arguments: [feedURL, feedURL, "img", "desc"]
      )
      let podcastID = db.lastInsertedRowID
      for (index, offset) in pubDateOffsetsDays.enumerated() {
        let pubDate = now.addingTimeInterval(-offset * 86400)
        try db.execute(
          sql: """
            INSERT INTO episode (podcastId, guid, mediaURL, title, pubDate)
            VALUES (?, ?, ?, ?, ?)
            """,
          arguments: [
            podcastID,
            "\(feedURL)-\(index)",
            "\(feedURL)-media-\(index)",
            "Episode \(index)",
            pubDate,
          ]
        )
      }
      return podcastID
    }
  }
}
