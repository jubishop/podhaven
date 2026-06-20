// Copyright Justin Bishop, 2026

import Foundation
import GRDB
import Testing

@testable import PodHaven

@Suite("of v66 migration tests", .container)
class V66MigrationTests {
  private let appDB = AppDB.inMemory(migrate: false)
  private let migrator: DatabaseMigrator
  private static let referenceDate = Date(timeIntervalSinceReferenceDate: 800_000_000)

  init() async throws {
    self.migrator = Schema.makeMigrator()
  }

  private static func seed(
    _ db: Database,
    feedURL: String,
    staleInferredCadence: String?,
    episodeCount: Int,
    spacingHours: Double
  ) throws {
    try db.execute(
      sql: """
        INSERT INTO podcast (feedURL, title, image, description, inferredFreshnessCadence)
        VALUES (?, ?, ?, ?, ?)
        """,
      arguments: [feedURL, "T", "img", "desc", staleInferredCadence]
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

  @Test("v66 realigns cached inferred cadence with runtime buckets")
  func realignsCachedInferredCadence() async throws {
    try migrator.migrate(appDB.unsafeTestDB, upTo: "v65")
    try await appDB.unsafeTestDB.write { db in
      try Self.seed(
        db,
        feedURL: "two-hour",
        staleInferredCadence: "hourly",
        episodeCount: 5,
        spacingHours: 2
      )
      try Self.seed(
        db,
        feedURL: "seventeen-hour",
        staleInferredCadence: "daily",
        episodeCount: 5,
        spacingHours: 17
      )
      try Self.seed(
        db,
        feedURL: "sparse",
        staleInferredCadence: nil,
        episodeCount: 2,
        spacingHours: 24
      )
      try Self.seed(
        db,
        feedURL: "empty",
        staleInferredCadence: "weekly",
        episodeCount: 0,
        spacingHours: 0
      )
    }

    try migrator.migrate(appDB.unsafeTestDB, upTo: "v66")

    #expect(try await inferredCadence(feedURL: "two-hour") == "twiceDaily")
    #expect(try await inferredCadence(feedURL: "seventeen-hour") == "twiceDaily")
    #expect(try await inferredCadence(feedURL: "sparse") == "weekly")
    #expect(try await inferredCadence(feedURL: "empty") == nil)
  }
}
