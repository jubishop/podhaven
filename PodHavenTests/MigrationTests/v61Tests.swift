// Copyright Justin Bishop, 2026

import Foundation
import GRDB
import Testing

@testable import PodHaven

@Suite("of v61 migration tests", .container)
class V61MigrationTests {
  private let appDB = AppDB.inMemory(migrate: false)
  private let migrator: DatabaseMigrator

  init() async throws {
    self.migrator = Schema.makeMigrator()
  }

  // Seed one podcast and two episodes (max id 511) at v60 so the backfill has a
  // determinate high-water mark.
  private func seedEpisodesAtV60() async throws {
    try migrator.migrate(appDB.unsafeTestDB, upTo: "v60")

    try await appDB.unsafeTestDB.write { db in
      try db.execute(
        sql: """
          INSERT INTO podcast (
            id, feedURL, title, image, description, link, lastUpdate,
            subscriptionDate, creationDate, defaultPlaybackRate,
            queueAllEpisodes, cacheAllEpisodes, notifyNewEpisodes, iTunesID,
            contentUpdatedAt
          ) VALUES (
            500, 'https://example.com/v61.xml', 'V61 Podcast',
            'https://example.com/img.jpg', 'Description',
            NULL, '2024-01-01 00:00:00', NULL, '2024-01-01 00:00:00',
            1.0, 'never', 'never', 0, NULL, '2024-01-01 00:00:00'
          )
          """
      )
      for (id, guid, mediaURL) in [
        (510, "guid-1", "https://example.com/ep-510.mp3"),
        (511, "guid-2", "https://example.com/ep-511.mp3"),
      ] {
        try db.execute(
          sql: """
            INSERT INTO episode (
              id, podcastId, guid, mediaURL, title, pubDate, creationDate,
              contentUpdatedAt, currentTime, maxPlaybackTime, saveInCache,
              downloading
            ) VALUES (
              ?, 500, ?, ?, 'Ep',
              '2024-02-01 00:00:00', '2024-02-01 00:00:00', '2024-02-01 00:00:00',
              0, 0, 0, 0
            )
            """,
          arguments: [id, guid, mediaURL]
        )
      }
    }
  }

  @Test("v61 adds a nullable INTEGER lastSeenEpisodeId column to smartList")
  func addsColumn() async throws {
    try migrator.migrate(appDB.unsafeTestDB, upTo: "v61")

    let info = try await appDB.unsafeTestDB.read { db -> (type: String, notnull: Int)? in
      for row in try Row.fetchAll(db, sql: "PRAGMA table_info(smartList)")
      where (row["name"] as String) == "lastSeenEpisodeId" {
        return (row["type"] as String, row["notnull"] as Int)
      }
      return nil
    }

    let column = try #require(info)
    #expect(column.type == "INTEGER")
    #expect(column.notnull == 0)
  }

  @Test("v61 backfills the watermark to the newest episode id")
  func backfillsToMaxEpisodeId() async throws {
    try await seedEpisodesAtV60()

    try migrator.migrate(appDB.unsafeTestDB, upTo: "v61")

    let watermarks = try await appDB.unsafeTestDB.read { db in
      try Int64.fetchAll(db, sql: "SELECT lastSeenEpisodeId FROM smartList")
    }
    // The v54 seed shipped 10 lists; every one starts seen at the top id.
    #expect(!watermarks.isEmpty)
    #expect(watermarks.allSatisfy { $0 == 511 })
  }

  @Test("v61 leaves the watermark NULL when the library is empty")
  func nullWhenNoEpisodes() async throws {
    try migrator.migrate(appDB.unsafeTestDB, upTo: "v61")

    let nonNullCount = try await appDB.unsafeTestDB.read { db in
      try Int.fetchOne(
        db,
        sql: "SELECT COUNT(*) FROM smartList WHERE lastSeenEpisodeId IS NOT NULL"
      ) ?? -1
    }
    #expect(nonNullCount == 0)
  }
}
