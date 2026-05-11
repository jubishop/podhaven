// Copyright Justin Bishop, 2026

import Foundation
import GRDB
import Testing

@testable import PodHaven

@Suite("of v45 migration tests", .container)
class V45MigrationTests {
  private let appDB = AppDB.inMemory(migrate: false)
  private let migrator: DatabaseMigrator

  init() async throws {
    self.migrator = Schema.makeMigrator()
  }

  // MARK: - Fixture

  // Seed at v44 with one podcast, one episode, and one episodeEmbedding row.
  // The embedding's creationDate is set to a fixed past instant so the v45
  // backfill (verificationDate := creationDate) can be asserted exactly.
  private func populateAtV44() async throws {
    try migrator.migrate(appDB.db, upTo: "v44")

    try await appDB.db.write { db in
      try db.execute(
        sql: """
          INSERT INTO podcast (
            id, feedURL, title, image, description, link, lastUpdate,
            subscriptionDate, creationDate, defaultPlaybackRate,
            queueAllEpisodes, cacheAllEpisodes, notifyNewEpisodes, iTunesID,
            contentUpdatedAt
          ) VALUES (
            500, 'https://example.com/v45.xml', 'V45 Podcast',
            'https://example.com/img.jpg', 'Description',
            NULL, '2024-01-01 00:00:00', NULL, '2024-01-01 00:00:00',
            1.0, 'never', 'never', 0, NULL, '2024-01-01 00:00:00'
          )
          """
      )
      try db.execute(
        sql: """
          INSERT INTO episode (
            id, podcastId, guid, mediaURL, title, pubDate, creationDate,
            contentUpdatedAt, currentTime, maxPlaybackTime, saveInCache,
            downloading
          ) VALUES (
            510, 500, 'guid-1', 'https://example.com/ep.mp3',
            'Episode', '2024-02-01 00:00:00', '2024-02-01 00:00:00',
            '2024-02-01 00:00:00', 0, 0, 0, 0
          )
          """
      )
      try db.execute(
        sql: """
          INSERT INTO episodeEmbedding (
            episodeId, vector, sourceHash, embeddingRevision, dimension,
            creationDate
          ) VALUES (
            510, x'00', 'hash', 1, 3,
            '2024-03-01 12:34:56'
          )
          """
      )
    }
  }

  // MARK: - Column Existence

  @Test("v45 adds verificationDate column to episodeEmbedding")
  func columnAddedToEpisodeEmbedding() async throws {
    try await populateAtV44()

    let columnsBefore = try await appDB.db.read { db in
      try Row.fetchAll(db, sql: "PRAGMA table_info(episodeEmbedding)")
        .map { $0["name"] as String }
    }
    #expect(!columnsBefore.contains("verificationDate"))

    try migrator.migrate(appDB.db, upTo: "v45")

    let columnsAfter = try await appDB.db.read { db in
      try Row.fetchAll(db, sql: "PRAGMA table_info(episodeEmbedding)")
        .map { ($0["name"] as String, $0["notnull"] as Int) }
    }
    let verification = columnsAfter.first { $0.0 == "verificationDate" }
    #expect(verification != nil)
    #expect(verification?.1 == 1)
  }

  // MARK: - Backfill

  // Existing embeddings need verificationDate to inherit creationDate so the
  // first post-v45 run of episodesNeedingEmbeddings sees the same shape it
  // saw at v44 — otherwise every previously-fresh embedding would suddenly
  // look stale (contentUpdatedAt > verificationDate of 0).
  @Test("v45 backfills verificationDate from creationDate on existing rows")
  func backfillFromCreationDate() async throws {
    try await populateAtV44()
    try migrator.migrate(appDB.db, upTo: "v45")

    try await appDB.db.read { db in
      let row = try #require(
        try Row.fetchOne(
          db,
          sql: "SELECT creationDate, verificationDate FROM episodeEmbedding WHERE episodeId = 510"
        )
      )
      #expect((row["creationDate"] as String) == "2024-03-01 12:34:56")
      #expect((row["verificationDate"] as String) == "2024-03-01 12:34:56")
    }
  }
}
