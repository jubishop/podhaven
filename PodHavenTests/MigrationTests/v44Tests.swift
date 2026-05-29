// Copyright Justin Bishop, 2026

import Foundation
import GRDB
import Testing

@testable import PodHaven

@Suite("of v44 migration tests", .container)
class V44MigrationTests {
  private let appDB = AppDB.inMemory(migrate: false)
  private let migrator: DatabaseMigrator

  init() async throws {
    self.migrator = Schema.makeMigrator()
  }

  // MARK: - Fixture

  private struct FixtureIDs: Sendable {
    let podcast: Int64
    let episodeWithStaleTaskID: Int64
    let episodeWithoutTaskID: Int64
  }

  // Seed at v43 (the last schema with episode.downloadTaskID) with one row
  // that holds a stale downloadTaskID value — exactly the pattern that, in
  // production, used to collide with a freshly-assigned URLSession
  // taskIdentifier and corrupt the cached file of an unrelated episode.
  private func populateAtV43() async throws -> FixtureIDs {
    try migrator.migrate(appDB.unsafeTestDB, upTo: "v43")

    return try await appDB.unsafeTestDB.write { db in
      try db.execute(
        sql: """
          INSERT INTO podcast (
            id, feedURL, title, image, description, link, lastUpdate,
            subscriptionDate, creationDate, defaultPlaybackRate,
            queueAllEpisodes, cacheAllEpisodes, notifyNewEpisodes, iTunesID,
            contentUpdatedAt
          ) VALUES (
            900, 'https://example.com/v44.xml', 'V44 Podcast',
            'https://example.com/img.jpg', 'Description',
            NULL, '2024-01-01 00:00:00', NULL, '2023-12-31 12:00:00',
            1.5, 'never', 'never', 0, NULL, '2023-12-31 12:00:00'
          )
          """
      )

      try db.execute(
        sql: """
          INSERT INTO episode (
            id, podcastId, guid, mediaURL, title, pubDate, creationDate,
            contentUpdatedAt, currentTime, maxPlaybackTime, saveInCache,
            downloadTaskID
          ) VALUES (
            910, 900, 'guid-stale', 'https://example.com/stale.mp3',
            'Stale Task', '2024-02-01 00:00:00', '2024-02-01 00:00:00',
            '2024-02-01 00:00:00', 0, 0, 0, 7
          )
          """
      )
      let stale = db.lastInsertedRowID

      try db.execute(
        sql: """
          INSERT INTO episode (
            id, podcastId, guid, mediaURL, title, pubDate, creationDate,
            contentUpdatedAt, currentTime, maxPlaybackTime, saveInCache,
            downloadTaskID
          ) VALUES (
            911, 900, 'guid-clean', 'https://example.com/clean.mp3',
            'No Task', '2024-02-02 00:00:00', '2024-02-02 00:00:00',
            '2024-02-02 00:00:00', 0, 0, 0, NULL
          )
          """
      )
      let clean = db.lastInsertedRowID

      return FixtureIDs(
        podcast: 900,
        episodeWithStaleTaskID: stale,
        episodeWithoutTaskID: clean
      )
    }
  }

  // MARK: - Schema Shape

  @Test("v44 drops downloadTaskID and adds downloading column")
  func columnsRenamed() async throws {
    _ = try await populateAtV43()
    try migrator.migrate(appDB.unsafeTestDB, upTo: "v44")

    try await appDB.unsafeTestDB.read { db in
      let cols = try Row.fetchAll(db, sql: "PRAGMA table_info('episode')")
      let names = Set(cols.compactMap { $0["name"] as? String })
      #expect(!names.contains("downloadTaskID"))
      #expect(names.contains("downloading"))
    }
  }

  @Test("v44 wipes any prior downloadTaskID values to downloading=false")
  func staleTaskIDsErased() async throws {
    let ids = try await populateAtV43()
    try migrator.migrate(appDB.unsafeTestDB, upTo: "v44")

    try await appDB.unsafeTestDB.read { db in
      let staleRow = try Row.fetchOne(
        db,
        sql: "SELECT downloading FROM episode WHERE id = ?",
        arguments: [ids.episodeWithStaleTaskID]
      )!
      #expect((staleRow["downloading"] as? Int64) == 0)

      let cleanRow = try Row.fetchOne(
        db,
        sql: "SELECT downloading FROM episode WHERE id = ?",
        arguments: [ids.episodeWithoutTaskID]
      )!
      #expect((cleanRow["downloading"] as? Int64) == 0)
    }
  }

  @Test("v44 does not enforce UNIQUE on downloading — duplicates allowed")
  func noUniqueOnDownloading() async throws {
    let ids = try await populateAtV43()
    try migrator.migrate(appDB.unsafeTestDB, upTo: "v44")

    try await appDB.unsafeTestDB.write { db in
      try db.execute(
        sql: "UPDATE episode SET downloading = 1 WHERE id IN (?, ?)",
        arguments: [ids.episodeWithStaleTaskID, ids.episodeWithoutTaskID]
      )
    }

    try await appDB.unsafeTestDB.read { db in
      let count = try Int.fetchOne(
        db,
        sql: "SELECT COUNT(*) FROM episode WHERE downloading = 1"
      )!
      #expect(count == 2)
    }
  }

  // MARK: - Other Episode Constraints Survived

  @Test("episode (guid, mediaURL) UNIQUE still enforced after v44 rebuild")
  func compoundUniqueGuidMediaURL() async throws {
    let ids = try await populateAtV43()
    try migrator.migrate(appDB.unsafeTestDB, upTo: "v44")

    await #expect(throws: DatabaseError.self) {
      try await self.appDB.unsafeTestDB.write { db in
        try db.execute(
          sql: """
            INSERT INTO episode (
              podcastId, guid, mediaURL, title, pubDate
            ) VALUES (?, 'guid-stale', 'https://example.com/stale.mp3', 'Dup', ?)
            """,
          arguments: [ids.podcast, "2025-01-01 00:00:00"]
        )
      }
    }
  }

  @Test("episode queueOrder CHECK still rejects negative values after v44 rebuild")
  func queueOrderCheckEnforced() async throws {
    let ids = try await populateAtV43()
    try migrator.migrate(appDB.unsafeTestDB, upTo: "v44")

    await #expect(throws: DatabaseError.self) {
      try await self.appDB.unsafeTestDB.write { db in
        try db.execute(
          sql: """
            INSERT INTO episode (
              podcastId, guid, mediaURL, title, pubDate, queueOrder
            ) VALUES (?, 'guid-neg', 'https://example.com/neg.mp3', 'Neg', ?, -1)
            """,
          arguments: [ids.podcast, "2025-01-01 00:00:00"]
        )
      }
    }
  }

  @Test("episode rating CHECK still rejects unknown values after v44 rebuild")
  func ratingCheckEnforced() async throws {
    let ids = try await populateAtV43()
    try migrator.migrate(appDB.unsafeTestDB, upTo: "v44")

    await #expect(throws: DatabaseError.self) {
      try await self.appDB.unsafeTestDB.write { db in
        try db.execute(
          sql: """
            INSERT INTO episode (
              podcastId, guid, mediaURL, title, pubDate, rating
            ) VALUES (?, 'guid-bad', 'https://example.com/bad.mp3', 'Bad', ?, 'meh')
            """,
          arguments: [ids.podcast, "2025-01-01 00:00:00"]
        )
      }
    }
  }

  // MARK: - Indexes Recreated

  @Test("v44 preserves all expected episode indexes")
  func indexesRecreated() async throws {
    _ = try await populateAtV43()
    try migrator.migrate(appDB.unsafeTestDB, upTo: "v44")

    try await appDB.unsafeTestDB.read { db in
      let rows = try Row.fetchAll(
        db,
        sql:
          "SELECT name FROM sqlite_master WHERE type = 'index' AND tbl_name = 'episode'"
      )
      let names = Set(rows.compactMap { $0["name"] as? String })
      #expect(names.contains("episode_on_podcastId"))
      #expect(names.contains("episode_on_guid"))
      #expect(names.contains("episode_on_mediaURL"))
      #expect(names.contains("episode_on_queueOrder"))
      #expect(names.contains("episode_on_pubDate"))
    }
  }
}
