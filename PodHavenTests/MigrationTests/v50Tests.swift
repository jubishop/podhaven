// Copyright Justin Bishop, 2026

import Foundation
import GRDB
import Testing

@testable import PodHaven

@Suite("of v50 migration tests", .container)
class V50MigrationTests {
  private let appDB = AppDB.inMemory(migrate: false)
  private let migrator: DatabaseMigrator
  // Fixed reference so the backfill's julianday math is deterministic. Static so
  // the seeding helper stays free of `self` capture inside GRDB's @Sendable
  // write closure.
  private static let referenceDate = Date(timeIntervalSinceReferenceDate: 800_000_000)

  init() async throws {
    self.migrator = Schema.makeMigrator()
  }

  // Inserts a podcast and `episodeCount` episodes whose pubDates step back from
  // referenceDate by `spacingHours` each, producing a uniform median gap.
  private static func seed(
    _ db: Database,
    feedURL: String,
    cadence: String? = nil,
    episodeCount: Int,
    spacingHours: Double
  ) throws {
    try db.execute(
      sql: """
        INSERT INTO podcast (feedURL, title, image, description, freshnessCadence)
        VALUES (?, ?, ?, ?, ?)
        """,
      arguments: [feedURL, "T", "img", "desc", cadence]
    )
    let podcastId = db.lastInsertedRowID
    for index in 0..<episodeCount {
      let pubDate = Self.referenceDate.addingTimeInterval(-Double(index) * spacingHours * 3600)
      try db.execute(
        sql: """
          INSERT INTO episode (podcastId, guid, mediaURL, title, pubDate)
          VALUES (?, ?, ?, ?, ?)
          """,
        arguments: [
          podcastId, "\(feedURL)-guid-\(index)", "\(feedURL)-media-\(index)",
          "Episode \(index)", pubDate,
        ]
      )
    }
  }

  private func inferredCadence(feedURL: String) async throws -> String? {
    try await appDB.unsafeTestDB.read { db in
      try String.fetchOne(
        db,
        sql: "SELECT inferredFreshnessCadence FROM podcast WHERE feedURL = ?",
        arguments: [feedURL]
      )
    }
  }

  @Test("v50 backfills inferred cadence by bucketing the median episode spacing")
  func backfillsCadences() async throws {
    try migrator.migrate(appDB.unsafeTestDB, upTo: "v49")
    try await appDB.unsafeTestDB.write { db in
      try Self.seed(db, feedURL: "hourly", episodeCount: 5, spacingHours: 1)
      try Self.seed(db, feedURL: "daily", episodeCount: 5, spacingHours: 24)
      try Self.seed(db, feedURL: "weekly", episodeCount: 5, spacingHours: 24 * 7)
      try Self.seed(db, feedURL: "monthly", episodeCount: 4, spacingHours: 24 * 30)
      try Self.seed(db, feedURL: "evergreen", episodeCount: 4, spacingHours: 24 * 60)
      // Fewer than 3 episodes mirrors infer's sparse fallback: left NULL.
      try Self.seed(db, feedURL: "sparse", episodeCount: 2, spacingHours: 24)
      try Self.seed(db, feedURL: "empty", episodeCount: 0, spacingHours: 0)
    }

    try migrator.migrate(appDB.unsafeTestDB, upTo: "v50")

    #expect(try await inferredCadence(feedURL: "hourly") == "hourly")
    #expect(try await inferredCadence(feedURL: "daily") == "daily")
    #expect(try await inferredCadence(feedURL: "weekly") == "weekly")
    #expect(try await inferredCadence(feedURL: "monthly") == "monthly")
    #expect(try await inferredCadence(feedURL: "evergreen") == "evergreen")
    #expect(try await inferredCadence(feedURL: "sparse") == nil)
    #expect(try await inferredCadence(feedURL: "empty") == nil)
  }

  @Test("v50 backfills the inferred column independently of a manual override")
  func backfillsAlongsideManualOverride() async throws {
    try migrator.migrate(appDB.unsafeTestDB, upTo: "v49")
    try await appDB.unsafeTestDB.write { db in
      // Manual override says daily, but the episodes are weekly-spaced. The
      // inferred column reflects the data so clearing the override later
      // resolves to the real cadence without waiting for a refresh.
      try Self.seed(
        db,
        feedURL: "manual",
        cadence: "daily",
        episodeCount: 5,
        spacingHours: 24 * 7
      )
    }

    try migrator.migrate(appDB.unsafeTestDB, upTo: "v50")

    // Extract Sendable scalars inside the read so the async overload applies
    // (a `Row` would cross the actor boundary non-Sendable).
    let cadences = try await appDB.unsafeTestDB.read { db -> (manual: String?, inferred: String?) in
      guard
        let row = try Row.fetchOne(
          db,
          sql: """
            SELECT freshnessCadence, inferredFreshnessCadence
            FROM podcast WHERE feedURL = ?
            """,
          arguments: ["manual"]
        )
      else { return (nil, nil) }
      return (row["freshnessCadence"], row["inferredFreshnessCadence"])
    }
    #expect(cadences.manual == "daily")
    #expect(cadences.inferred == "weekly")
  }

  @Test("v50 inferredFreshnessCadence accepts valid cadences and NULL, rejects others")
  func enforcesCadenceCheck() async throws {
    try migrator.migrate(appDB.unsafeTestDB, upTo: "v50")

    try await appDB.unsafeTestDB.write { db in
      try db.execute(
        sql: """
          INSERT INTO podcast (feedURL, title, image, description, inferredFreshnessCadence)
          VALUES ('ok', 'T', 'img', 'desc', 'twiceWeekly')
          """
      )
      // NULL (not yet inferred) stays valid.
      try db.execute(
        sql:
          "INSERT INTO podcast (feedURL, title, image, description) VALUES ('auto', 'T', 'img', 'desc')"
      )
    }

    await #expect(throws: DatabaseError.self) {
      try await self.appDB.unsafeTestDB.write { db in
        try db.execute(
          sql: """
            INSERT INTO podcast (feedURL, title, image, description, inferredFreshnessCadence)
            VALUES ('bad', 'T', 'img', 'desc', 'yearly')
            """
        )
      }
    }
  }
}
