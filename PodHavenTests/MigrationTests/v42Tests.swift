// Copyright Justin Bishop, 2026

import Foundation
import GRDB
import Testing

@testable import PodHaven

@Suite("of v42 migration tests", .container)
class V42MigrationTests {
  private let appDB = AppDB.inMemory(migrate: false)
  private let migrator: DatabaseMigrator

  init() async throws {
    self.migrator = Schema.makeMigrator()
  }

  // MARK: - Fixture

  private struct FixtureIDs: Sendable {
    let podcast: Int64
    let episodeLoved: Int64
    let episodeLiked: Int64
    let episodeDisliked: Int64
    let episodeUnrated: Int64
    let episodeWithCoverage: Int64
  }

  /// Populate at v41 with rows covering every existing rating value (the v35
  /// CHECK set: loved/liked/disliked/NULL) and the v41 playback-coverage
  /// columns, so we can verify byte-for-byte preservation across the v42
  /// rebuild.
  private func populateAtV41() async throws -> FixtureIDs {
    try migrator.migrate(appDB.db, upTo: "v41")

    return try await appDB.db.write { db in
      try db.execute(
        sql: """
          INSERT INTO podcast (
            id, feedURL, title, image, description, link, lastUpdate,
            subscriptionDate, creationDate, defaultPlaybackRate,
            queueAllEpisodes, cacheAllEpisodes, notifyNewEpisodes, iTunesID,
            contentUpdatedAt
          ) VALUES (
            500, 'https://example.com/v42.xml', 'V42 Podcast',
            'https://example.com/img.jpg', 'Description',
            NULL, '2024-01-01 00:00:00', NULL, '2023-12-31 12:00:00',
            1.5, 'never', 'never', 0, NULL, '2023-12-31 12:00:00'
          )
          """
      )

      let loved = try Self.insertEpisode(
        db,
        id: 600,
        podcastID: 500,
        guid: "guid-loved",
        rating: "loved",
        ratingDate: "2024-01-02 10:00:00"
      )
      let liked = try Self.insertEpisode(
        db,
        id: 601,
        podcastID: 500,
        guid: "guid-liked",
        rating: "liked",
        ratingDate: "2024-01-02 11:00:00"
      )
      let disliked = try Self.insertEpisode(
        db,
        id: 602,
        podcastID: 500,
        guid: "guid-disliked",
        rating: "disliked",
        ratingDate: "2024-01-02 12:00:00"
      )
      let unrated = try Self.insertEpisode(
        db,
        id: 603,
        podcastID: 500,
        guid: "guid-unrated",
        rating: nil,
        ratingDate: nil
      )

      let coverageBlob = Data([0xFF, 0x80, 0x00, 0x01])
      try db.execute(
        sql: """
          INSERT INTO episode (
            id, podcastId, guid, mediaURL, title, pubDate,
            creationDate, contentUpdatedAt, currentTime, saveInCache,
            maxPlaybackTime, playbackCoverage, lastPlayedDate
          ) VALUES (
            604, 500, 'guid-coverage', 'https://example.com/ep-cov.mp3',
            'With Coverage', '2024-01-05 00:00:00',
            '2024-01-05 00:00:00', '2024-01-05 00:00:00', 120, 0,
            120, ?, '2024-01-06 09:00:00'
          )
          """,
        arguments: [coverageBlob]
      )
      let coverage = db.lastInsertedRowID

      // Child rows so the rebuild has FK references to validate. The episode
      // table is rebuilt under defer_foreign_keys; if anything reassigned
      // episode IDs, these would be left dangling.
      try db.execute(
        sql: """
          INSERT INTO tag (id, name, creationDate)
          VALUES (700, 'tech', '2024-01-01 00:00:00'),
                 (701, 'news', '2024-01-01 00:00:00')
          """
      )
      try db.execute(
        sql: """
          INSERT INTO podcastTag (podcastId, tagId) VALUES
            (500, 700), (500, 701)
          """
      )
      try db.execute(
        sql: """
          INSERT INTO episodeTag (episodeId, tagId) VALUES
            (?, 700), (?, 701), (?, 700)
          """,
        arguments: [loved, loved, liked]
      )

      let vector = Data([0x10, 0x20, 0x30, 0x40])
      try db.execute(
        sql: """
          INSERT INTO episodeEmbedding (
            episodeId, vector, sourceHash, embeddingRevision, dimension,
            creationDate
          ) VALUES (?, ?, 'hash-loved', 1, 3, '2024-01-03 00:00:00')
          """,
        arguments: [loved, vector]
      )
      try db.execute(
        sql: """
          INSERT INTO episodeEmbedding (
            episodeId, vector, sourceHash, embeddingRevision, dimension,
            creationDate
          ) VALUES (?, ?, 'hash-cov', 2, 3, '2024-01-06 00:00:00')
          """,
        arguments: [coverage, vector]
      )
      try db.execute(
        sql: """
          INSERT INTO podcastEmbedding (
            podcastId, vector, sourceHash, embeddingRevision, dimension,
            creationDate
          ) VALUES (500, ?, 'hash-p500', 1, 3, '2024-01-03 00:00:00')
          """,
        arguments: [vector]
      )

      return FixtureIDs(
        podcast: 500,
        episodeLoved: loved,
        episodeLiked: liked,
        episodeDisliked: disliked,
        episodeUnrated: unrated,
        episodeWithCoverage: coverage
      )
    }
  }

  private static func insertEpisode(
    _ db: Database,
    id: Int64,
    podcastID: Int64,
    guid: String,
    rating: String?,
    ratingDate: String?
  ) throws -> Int64 {
    try db.execute(
      sql: """
        INSERT INTO episode (
          id, podcastId, guid, mediaURL, title, pubDate,
          creationDate, contentUpdatedAt, rating, ratingDate, saveInCache,
          currentTime, maxPlaybackTime
        ) VALUES (
          ?, ?, ?, ?, ?, '2024-01-02 00:00:00',
          '2024-01-02 00:00:00', '2024-01-02 00:00:00', ?, ?, 0, 0, 0
        )
        """,
      arguments: [
        id, podcastID, guid, "https://example.com/\(guid).mp3",
        "Title for \(guid)", rating, ratingDate,
      ]
    )
    return id
  }

  // MARK: - Data Preservation

  @Test("all episode column values preserved byte-for-byte through v42 rebuild")
  func episodeDataPreserved() async throws {
    _ = try await populateAtV41()

    let preservedColumns = [
      "id", "podcastId", "guid", "mediaURL", "title", "pubDate",
      "duration", "description", "link", "image", "finishDate",
      "currentTime", "queueOrder", "queueDate", "cachedFilename",
      "downloadTaskID", "creationDate", "saveInCache", "maxPlaybackTime",
      "rating", "ratingDate", "contentUpdatedAt",
      "playbackCoverage", "lastPlayedDate",
    ]
    let selectSQL =
      "SELECT \(preservedColumns.joined(separator: ", ")) FROM episode ORDER BY id"

    let before = try await appDB.db.read { db in
      try Row.fetchAll(db, sql: selectSQL).map { $0.asDictionary() }
    }

    try migrator.migrate(appDB.db, upTo: "v42")

    let after = try await appDB.db.read { db in
      try Row.fetchAll(db, sql: selectSQL).map { $0.asDictionary() }
    }

    #expect(before == after)
  }

  @Test("podcast table left untouched by v42 (only episode is rebuilt)")
  func podcastUnchanged() async throws {
    _ = try await populateAtV41()

    let before = try await appDB.db.read { db in
      try Row.fetchAll(db, sql: "SELECT * FROM podcast ORDER BY id")
        .map { $0.asDictionary() }
    }

    try migrator.migrate(appDB.db, upTo: "v42")

    let after = try await appDB.db.read { db in
      try Row.fetchAll(db, sql: "SELECT * FROM podcast ORDER BY id")
        .map { $0.asDictionary() }
    }

    #expect(before == after)
  }

  // MARK: - Widened CHECK Constraint

  @Test("v42 widens rating CHECK to accept 'notInterested'")
  func ratingCheckAcceptsNotInterested() async throws {
    let ids = try await populateAtV41()
    try migrator.migrate(appDB.db, upTo: "v42")

    try await appDB.db.write { db in
      try db.execute(
        sql: "UPDATE episode SET rating = 'notInterested' WHERE id = ?",
        arguments: [ids.episodeUnrated]
      )
    }

    let stored = try await appDB.db.read { db in
      try String.fetchOne(
        db,
        sql: "SELECT rating FROM episode WHERE id = ?",
        arguments: [ids.episodeUnrated]
      )
    }
    #expect(stored == "notInterested")
  }

  @Test("v42 still accepts the existing rating values")
  func ratingCheckStillAcceptsExistingValues() async throws {
    let ids = try await populateAtV41()
    try migrator.migrate(appDB.db, upTo: "v42")

    let ratings = try await appDB.db.read { db in
      try Row.fetchAll(
        db,
        sql: "SELECT id, rating FROM episode ORDER BY id"
      )
      .map { ($0["id"] as Int64, $0["rating"] as String?) }
    }
    #expect(ratings.contains { $0.0 == ids.episodeLoved && $0.1 == "loved" })
    #expect(ratings.contains { $0.0 == ids.episodeLiked && $0.1 == "liked" })
    #expect(ratings.contains { $0.0 == ids.episodeDisliked && $0.1 == "disliked" })
    #expect(ratings.contains { $0.0 == ids.episodeUnrated && $0.1 == nil })
  }

  @Test("v42 rating CHECK still rejects unknown values")
  func ratingCheckRejectsInvalid() async throws {
    let ids = try await populateAtV41()
    try migrator.migrate(appDB.db, upTo: "v42")

    await #expect(throws: DatabaseError.self) {
      try await self.appDB.db.write { db in
        try db.execute(
          sql: "UPDATE episode SET rating = 'hated' WHERE id = ?",
          arguments: [ids.episodeUnrated]
        )
      }
    }
  }

  // MARK: - Triggers

  // v42 drops the episode_content_updated trigger before the table rebuild
  // and recreates it after the rename. Verify the recreated trigger fires.
  @Test("episode_content_updated trigger still fires after v42 rebuild")
  func triggerStillFires() async throws {
    let ids = try await populateAtV41()
    try migrator.migrate(appDB.db, upTo: "v42")

    let before = try await appDB.db.read { db in
      try String.fetchOne(
        db,
        sql: "SELECT contentUpdatedAt FROM episode WHERE id = ?",
        arguments: [ids.episodeLoved]
      )
    }

    try await appDB.db.write { db in
      try db.execute(
        sql: "UPDATE episode SET title = ? WHERE id = ?",
        arguments: ["Retitled after v42", ids.episodeLoved]
      )
    }

    let after = try await appDB.db.read { db in
      try String.fetchOne(
        db,
        sql: "SELECT contentUpdatedAt FROM episode WHERE id = ?",
        arguments: [ids.episodeLoved]
      )
    }
    #expect(after != before)
    #expect((after ?? "") > (before ?? ""))
  }

  @Test("episode_content_updated does NOT fire on non-content changes after v42")
  func triggerIgnoresNonContent() async throws {
    let ids = try await populateAtV41()
    try migrator.migrate(appDB.db, upTo: "v42")

    let before = try await appDB.db.read { db in
      try String.fetchOne(
        db,
        sql: "SELECT contentUpdatedAt FROM episode WHERE id = ?",
        arguments: [ids.episodeLoved]
      )
    }

    try await appDB.db.write { db in
      try db.execute(
        sql: "UPDATE episode SET currentTime = currentTime + 1 WHERE id = ?",
        arguments: [ids.episodeLoved]
      )
    }

    let after = try await appDB.db.read { db in
      try String.fetchOne(
        db,
        sql: "SELECT contentUpdatedAt FROM episode WHERE id = ?",
        arguments: [ids.episodeLoved]
      )
    }
    #expect(after == before)
  }

  // MARK: - Constraint Enforcement

  @Test("episode (podcastId, guid) UNIQUE still enforced after v42 rebuild")
  func compoundUniquePodcastGuid() async throws {
    let ids = try await populateAtV41()
    try migrator.migrate(appDB.db, upTo: "v42")

    await #expect(throws: DatabaseError.self) {
      try await self.appDB.db.write { db in
        try db.execute(
          sql: """
            INSERT INTO episode (podcastId, guid, mediaURL, title, pubDate)
            VALUES (?, 'guid-loved', 'https://example.com/dup.mp3', 'Dup', ?)
            """,
          arguments: [ids.podcast, "2025-01-01 00:00:00"]
        )
      }
    }
  }

  @Test("episode (podcastId, mediaURL) UNIQUE still enforced after v42 rebuild")
  func compoundUniquePodcastMediaURL() async throws {
    let ids = try await populateAtV41()
    try migrator.migrate(appDB.db, upTo: "v42")

    await #expect(throws: DatabaseError.self) {
      try await self.appDB.db.write { db in
        try db.execute(
          sql: """
            INSERT INTO episode (podcastId, guid, mediaURL, title, pubDate)
            VALUES (?, 'guid-distinct', 'https://example.com/guid-loved.mp3', 'Dup', ?)
            """,
          arguments: [ids.podcast, "2025-01-01 00:00:00"]
        )
      }
    }
  }

  @Test("episode (guid, mediaURL) UNIQUE still enforced after v42 rebuild")
  func compoundUniqueGuidMediaURL() async throws {
    _ = try await populateAtV41()
    // Insert a second podcast at v41 so we can attempt the cross-podcast
    // duplicate that only the (guid, mediaURL) UNIQUE catches.
    try await appDB.db.write { db in
      try db.execute(
        sql: """
          INSERT INTO podcast (
            id, feedURL, title, image, description, contentUpdatedAt
          ) VALUES (
            501, 'https://example.com/v42-2.xml', 'Other', 'img', 'desc',
            '2024-01-01 00:00:00'
          )
          """
      )
    }
    try migrator.migrate(appDB.db, upTo: "v42")

    await #expect(throws: DatabaseError.self) {
      try await self.appDB.db.write { db in
        try db.execute(
          sql: """
            INSERT INTO episode (podcastId, guid, mediaURL, title, pubDate)
            VALUES (501, 'guid-loved', 'https://example.com/guid-loved.mp3', 'Dup', ?)
            """,
          arguments: ["2025-01-01 00:00:00"]
        )
      }
    }
  }

  @Test("episode downloadTaskID UNIQUE still enforced after v42 rebuild")
  func downloadTaskIDUnique() async throws {
    let ids = try await populateAtV41()
    // Seed a downloadTaskID at v41 so the post-v42 conflict is on a real row.
    try await appDB.db.write { db in
      try db.execute(
        sql: "UPDATE episode SET downloadTaskID = 4242 WHERE id = ?",
        arguments: [ids.episodeUnrated]
      )
    }
    try migrator.migrate(appDB.db, upTo: "v42")

    await #expect(throws: DatabaseError.self) {
      try await self.appDB.db.write { db in
        try db.execute(
          sql: """
            INSERT INTO episode (
              podcastId, guid, mediaURL, title, pubDate, downloadTaskID
            ) VALUES (?, 'guid-dl', 'https://example.com/dl.mp3', 'Dup DL', ?, 4242)
            """,
          arguments: [ids.podcast, "2025-01-01 00:00:00"]
        )
      }
    }
  }

  @Test("episode queueOrder CHECK still rejects negative values after v42 rebuild")
  func queueOrderCheckEnforced() async throws {
    let ids = try await populateAtV41()
    try migrator.migrate(appDB.db, upTo: "v42")

    await #expect(throws: DatabaseError.self) {
      try await self.appDB.db.write { db in
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

  // MARK: - Child Tables

  // The episode rebuild runs under defer_foreign_keys, so child rows in
  // episodeTag and episodeEmbedding temporarily hang on FKs that point at
  // the dropped table. This test catches any regression that would silently
  // orphan or reorder them.
  @Test("child tables (embeddings, tag joins) unchanged by v42 rebuild")
  func childTablesPreserved() async throws {
    _ = try await populateAtV41()

    let capture = { [appDB] () async throws -> [String: [[String: DatabaseValue]]] in
      try await appDB.db.read { db in
        [
          "tag": try Row.fetchAll(db, sql: "SELECT * FROM tag ORDER BY id")
            .map { $0.asDictionary() },
          "podcastTag":
            try Row.fetchAll(
              db,
              sql: "SELECT * FROM podcastTag ORDER BY podcastId, tagId"
            )
            .map { $0.asDictionary() },
          "episodeTag":
            try Row.fetchAll(
              db,
              sql: "SELECT * FROM episodeTag ORDER BY episodeId, tagId"
            )
            .map { $0.asDictionary() },
          "episodeEmbedding":
            try Row.fetchAll(
              db,
              sql: "SELECT * FROM episodeEmbedding ORDER BY id"
            )
            .map { $0.asDictionary() },
          "podcastEmbedding":
            try Row.fetchAll(
              db,
              sql: "SELECT * FROM podcastEmbedding ORDER BY id"
            )
            .map { $0.asDictionary() },
        ]
      }
    }

    let before = try await capture()
    try migrator.migrate(appDB.db, upTo: "v42")
    let after = try await capture()

    #expect(before == after)
  }

  @Test("episode→tag CASCADE still cleans episodeTag rows after v42 rebuild")
  func episodeTagCascadeStillWorks() async throws {
    let ids = try await populateAtV41()
    try migrator.migrate(appDB.db, upTo: "v42")

    try await appDB.db.write { db in
      try db.execute(
        sql: "DELETE FROM episode WHERE id = ?",
        arguments: [ids.episodeLoved]
      )
    }

    let remaining = try await appDB.db.read { db in
      try Int.fetchOne(
        db,
        sql: "SELECT COUNT(*) FROM episodeTag WHERE episodeId = ?",
        arguments: [ids.episodeLoved]
      ) ?? -1
    }
    #expect(remaining == 0)
  }

  @Test("episode→embedding CASCADE still cleans episodeEmbedding rows after v42 rebuild")
  func episodeEmbeddingCascadeStillWorks() async throws {
    let ids = try await populateAtV41()
    try migrator.migrate(appDB.db, upTo: "v42")

    try await appDB.db.write { db in
      try db.execute(
        sql: "DELETE FROM episode WHERE id = ?",
        arguments: [ids.episodeWithCoverage]
      )
    }

    let remaining = try await appDB.db.read { db in
      try Int.fetchOne(
        db,
        sql: "SELECT COUNT(*) FROM episodeEmbedding WHERE episodeId = ?",
        arguments: [ids.episodeWithCoverage]
      ) ?? -1
    }
    #expect(remaining == 0)
  }

  // MARK: - Cascade & Integrity

  @Test("PRAGMA foreign_key_check passes after v42 rebuild")
  func foreignKeyIntegrityAfterRebuild() async throws {
    _ = try await populateAtV41()
    try migrator.migrate(appDB.db, upTo: "v42")

    let violations = try appDB.db.read { db -> [Row] in
      try Row.fetchAll(db, sql: "PRAGMA foreign_key_check")
    }
    #expect(violations.isEmpty)
  }

  @Test("podcast→episode CASCADE still wired after v42 rebuild")
  func cascadeStillWorks() async throws {
    let ids = try await populateAtV41()
    try migrator.migrate(appDB.db, upTo: "v42")

    try await appDB.db.write { db in
      try db.execute(
        sql: "DELETE FROM podcast WHERE id = ?",
        arguments: [ids.podcast]
      )
    }

    let remaining = try await appDB.db.read { db in
      try Int.fetchOne(
        db,
        sql: "SELECT COUNT(*) FROM episode WHERE podcastId = ?",
        arguments: [ids.podcast]
      ) ?? -1
    }
    #expect(remaining == 0)
  }

  // MARK: - AUTOINCREMENT

  @Test("episode AUTOINCREMENT continues from max id after v42 rebuild")
  func autoincrementContinues() async throws {
    _ = try await populateAtV41()
    try migrator.migrate(appDB.db, upTo: "v42")

    let newID = try await appDB.db.write { db in
      try db.execute(
        sql: """
          INSERT INTO episode (podcastId, guid, mediaURL, title, pubDate)
          VALUES (500, 'guid-post-v42', 'https://example.com/post.mp3',
                  'Post v42', '2025-01-01 00:00:00')
          """
      )
      return db.lastInsertedRowID
    }
    // Max existing id was 604.
    #expect(newID == 605)
  }
}

extension Row {
  fileprivate func asDictionary() -> [String: DatabaseValue] {
    var result: [String: DatabaseValue] = [:]
    for name in columnNames {
      let value: DatabaseValue = self[name]
      result[name] = value
    }
    return result
  }
}
