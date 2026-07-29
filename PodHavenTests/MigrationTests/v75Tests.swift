// Copyright Justin Bishop, 2026

import GRDB
import Testing

@testable import PodHaven

@Suite("of v75 migration tests", .container)
struct V75MigrationTests {
  private let appDB = AppDB.inMemory(migrate: false)
  private let migrator = Schema.makeMigrator()

  @Test("v75 adds a partial nonunique index for cache ownership lookups")
  func addsCachedFilenameIndex() async throws {
    try migrator.migrate(appDB.unsafeTestDB, upTo: "v74")
    try await appDB.unsafeTestDB.write { db in
      try db.execute(
        sql: """
          INSERT INTO podcast (
            id, feedURL, title, image, description
          ) VALUES (
            750, 'https://example.com/v75.xml', 'Cache Index',
            'https://example.com/v75.jpg', 'Description'
          )
          """
      )
      try db.execute(
        sql: """
          INSERT INTO episode (
            id, podcastId, guid, mediaURL, title, pubDate, cachedFilename
          ) VALUES
            (
              751, 750, 'v75-1', 'https://example.com/v75-1.mp3',
              'First Owner', '2026-01-01 00:00:00', 'shared-v75.mp3'
            ),
            (
              752, 750, 'v75-2', 'https://example.com/v75-2.mp3',
              'Second Owner', '2026-01-02 00:00:00', 'shared-v75.mp3'
            ),
            (
              753, 750, 'v75-3', 'https://example.com/v75-3.mp3',
              'Uncached', '2026-01-03 00:00:00', NULL
            )
          """
      )
    }

    let planBefore = try await cacheOwnershipPlan()
    #expect(planBefore.contains("SCAN episode"))

    try migrator.migrate(appDB.unsafeTestDB, upTo: "v75")

    let indexSQL = try await appDB.unsafeTestDB.read { db in
      try String.fetchOne(
        db,
        sql: """
          SELECT sql
          FROM sqlite_master
          WHERE type = 'index' AND name = 'episode_on_cachedFilename'
          """
      )
    }
    #expect(indexSQL?.contains("WHERE") == true)
    #expect(try await cacheOwnershipPlan().contains("episode_on_cachedFilename"))
    let sharedOwnerCount = try await appDB.unsafeTestDB.read { db in
      try Int.fetchOne(
        db,
        sql: "SELECT COUNT(*) FROM episode WHERE cachedFilename = 'shared-v75.mp3'"
      )
    }
    #expect(sharedOwnerCount == 2)
  }

  private func cacheOwnershipPlan() async throws -> String {
    try await appDB.unsafeTestDB.read { db in
      try Row.fetchAll(
        db,
        sql: """
          EXPLAIN QUERY PLAN
            SELECT COUNT(*)
            FROM episode
            WHERE cachedFilename = 'shared-v75.mp3'
          """
      )
      .map { $0["detail"] as String }
      .joined(separator: "\n")
    }
  }
}
