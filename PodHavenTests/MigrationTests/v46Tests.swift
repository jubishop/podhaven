// Copyright Justin Bishop, 2026

import Foundation
import GRDB
import Testing

@testable import PodHaven

@Suite("of v46 migration tests", .container)
class V46MigrationTests {
  private let appDB = AppDB.inMemory(migrate: false)
  private let migrator: DatabaseMigrator

  init() async throws {
    self.migrator = Schema.makeMigrator()
  }

  // MARK: - Fixture

  private struct FixtureIDs: Sendable {
    let podcastA: Int64
    let podcastB: Int64
    let sharedEpisode: Int64
    let otherEpisode: Int64
  }

  // Seed at v45 (the last schema before v46) with two podcasts and a "shared"
  // episode under podcast A whose (guid, mediaURL) podcast B will republish —
  // the overlapping-feed pattern the global UNIQUE key used to forbid.
  private func populateAtV45() async throws -> FixtureIDs {
    try migrator.migrate(appDB.unsafeTestDB, upTo: "v45")

    return try await appDB.unsafeTestDB.write { db in
      for (id, title) in [(900, "Podcast A"), (901, "Podcast B")] {
        try db.execute(
          sql: """
            INSERT INTO podcast (
              id, feedURL, title, image, description, link, lastUpdate,
              subscriptionDate, creationDate, defaultPlaybackRate,
              queueAllEpisodes, cacheAllEpisodes, notifyNewEpisodes, iTunesID,
              contentUpdatedAt
            ) VALUES (
              ?, ?, ?, 'https://example.com/img.jpg', 'Description',
              NULL, '2024-01-01 00:00:00', NULL, '2023-12-31 12:00:00',
              1.5, 'never', 'never', 0, NULL, '2023-12-31 12:00:00'
            )
            """,
          arguments: [id, "https://example.com/\(id).xml", title]
        )
      }

      try db.execute(
        sql: """
          INSERT INTO episode (
            id, podcastId, guid, mediaURL, title, pubDate, creationDate,
            contentUpdatedAt, currentTime, maxPlaybackTime, saveInCache,
            downloading
          ) VALUES (
            910, 900, 'shared-guid', 'https://example.com/shared.mp3',
            'Shared', '2024-02-01 00:00:00', '2024-02-01 00:00:00',
            '2024-02-01 00:00:00', 0, 0, 0, 1
          )
          """
      )
      let shared = db.lastInsertedRowID

      try db.execute(
        sql: """
          INSERT INTO episode (
            id, podcastId, guid, mediaURL, title, pubDate, creationDate,
            contentUpdatedAt, currentTime, maxPlaybackTime, saveInCache,
            downloading
          ) VALUES (
            911, 900, 'other-guid', 'https://example.com/other.mp3',
            'Other', '2024-02-02 00:00:00', '2024-02-02 00:00:00',
            '2024-02-02 00:00:00', 0, 0, 0, 0
          )
          """
      )
      let other = db.lastInsertedRowID

      return FixtureIDs(
        podcastA: 900,
        podcastB: 901,
        sharedEpisode: shared,
        otherEpisode: other
      )
    }
  }

  // MARK: - Global Key Dropped

  @Test("v46 lets two podcasts share the same (guid, mediaURL)")
  func crossPodcastDuplicateAllowed() async throws {
    let ids = try await populateAtV45()
    try migrator.migrate(appDB.unsafeTestDB, upTo: "v46")

    try await appDB.unsafeTestDB.write { db in
      try db.execute(
        sql: """
          INSERT INTO episode (
            podcastId, guid, mediaURL, title, pubDate
          ) VALUES (?, 'shared-guid', 'https://example.com/shared.mp3', 'Dup', ?)
          """,
        arguments: [ids.podcastB, "2025-01-01 00:00:00"]
      )
    }

    try await appDB.unsafeTestDB.read { db in
      let count = try Int.fetchOne(
        db,
        sql: """
          SELECT COUNT(*) FROM episode
          WHERE guid = 'shared-guid' AND mediaURL = 'https://example.com/shared.mp3'
          """
      )!
      #expect(count == 2)
    }
  }

  // MARK: - Per-Podcast Keys Survived

  @Test("episode (podcastId, guid) UNIQUE still enforced after v46 rebuild")
  func perPodcastGuidStillUnique() async throws {
    let ids = try await populateAtV45()
    try migrator.migrate(appDB.unsafeTestDB, upTo: "v46")

    await #expect(throws: DatabaseError.self) {
      try await self.appDB.unsafeTestDB.write { db in
        try db.execute(
          sql: """
            INSERT INTO episode (
              podcastId, guid, mediaURL, title, pubDate
            ) VALUES (?, 'shared-guid', 'https://example.com/new.mp3', 'Dup', ?)
            """,
          arguments: [ids.podcastA, "2025-01-01 00:00:00"]
        )
      }
    }
  }

  @Test("episode (podcastId, mediaURL) UNIQUE still enforced after v46 rebuild")
  func perPodcastMediaURLStillUnique() async throws {
    let ids = try await populateAtV45()
    try migrator.migrate(appDB.unsafeTestDB, upTo: "v46")

    await #expect(throws: DatabaseError.self) {
      try await self.appDB.unsafeTestDB.write { db in
        try db.execute(
          sql: """
            INSERT INTO episode (
              podcastId, guid, mediaURL, title, pubDate
            ) VALUES (?, 'new-guid', 'https://example.com/shared.mp3', 'Dup', ?)
            """,
          arguments: [ids.podcastA, "2025-01-01 00:00:00"]
        )
      }
    }
  }

  // MARK: - Data Preserved

  @Test("v46 preserves episode rows and downloading state through the rebuild")
  func dataPreserved() async throws {
    let ids = try await populateAtV45()
    try migrator.migrate(appDB.unsafeTestDB, upTo: "v46")

    try await appDB.unsafeTestDB.read { db in
      let count = try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM episode")!
      #expect(count == 2)

      let sharedRow = try Row.fetchOne(
        db,
        sql: "SELECT podcastId, guid, mediaURL, downloading FROM episode WHERE id = ?",
        arguments: [ids.sharedEpisode]
      )!
      #expect((sharedRow["podcastId"] as? Int64) == ids.podcastA)
      #expect((sharedRow["guid"] as? String) == "shared-guid")
      #expect((sharedRow["mediaURL"] as? String) == "https://example.com/shared.mp3")
      #expect((sharedRow["downloading"] as? Int64) == 1)

      let otherRow = try Row.fetchOne(
        db,
        sql: "SELECT downloading FROM episode WHERE id = ?",
        arguments: [ids.otherEpisode]
      )!
      #expect((otherRow["downloading"] as? Int64) == 0)
    }
  }

  // MARK: - Child Rows Survive

  // The rebuild drops the episode table. With foreign keys active, DROP TABLE
  // runs an implicit DELETE that would fire ON DELETE CASCADE and wipe every
  // episodeTag and episodeEmbedding row. Prove the rebuild preserves them.
  @Test("v46 rebuild does not cascade-delete episode child rows")
  func childRowsSurviveRebuild() async throws {
    let ids = try await populateAtV45()

    try await appDB.unsafeTestDB.write { db in
      try db.execute(sql: "INSERT INTO tag (id, name) VALUES (800, 'News')")
      try db.execute(
        sql: "INSERT INTO episodeTag (episodeId, tagId) VALUES (?, 800)",
        arguments: [ids.sharedEpisode]
      )
      try db.execute(
        sql: """
          INSERT INTO episodeEmbedding (
            episodeId, vector, sourceHash, embeddingRevision, dimension,
            creationDate, verificationDate
          ) VALUES (?, x'00010203', 'hash', 1, 4, ?, ?)
          """,
        arguments: [ids.sharedEpisode, "2024-02-01 00:00:00", "2024-02-01 00:00:00"]
      )
    }

    try migrator.migrate(appDB.unsafeTestDB, upTo: "v46")

    try await appDB.unsafeTestDB.read { db in
      let tagLinks = try Int.fetchOne(
        db,
        sql: "SELECT COUNT(*) FROM episodeTag WHERE episodeId = ?",
        arguments: [ids.sharedEpisode]
      )!
      #expect(tagLinks == 1)

      let embeddings = try Int.fetchOne(
        db,
        sql: "SELECT COUNT(*) FROM episodeEmbedding WHERE episodeId = ?",
        arguments: [ids.sharedEpisode]
      )!
      #expect(embeddings == 1)

      let fkViolations = try Row.fetchAll(db, sql: "PRAGMA foreign_key_check")
      #expect(fkViolations.isEmpty)
    }
  }

  // MARK: - Indexes Recreated

  @Test("v46 preserves all expected episode indexes")
  func indexesRecreated() async throws {
    _ = try await populateAtV45()
    try migrator.migrate(appDB.unsafeTestDB, upTo: "v46")

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
