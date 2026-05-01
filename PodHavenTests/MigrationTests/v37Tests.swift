// Copyright Justin Bishop, 2026

import Foundation
import GRDB
import Testing

@testable import PodHaven

@Suite("of v37 migration tests", .container)
class V37MigrationTests {
  private let appDB = AppDB.inMemory(migrate: false)
  private let migrator: DatabaseMigrator

  init() async throws {
    self.migrator = Schema.makeMigrator()
  }

  // MARK: - Fixture

  private struct FixtureIDs: Sendable {
    let podcastFull: Int64
    let podcastMinimal: Int64
    let episodeFull: Int64
    let episodeMinimal: Int64
    let episodeQueuedRated: Int64
    let episodeFinished: Int64
    let episodeSecondPodcast: Int64
    let tagA: Int64
    let tagB: Int64
  }

  /// Populates the database at v36 with rows spanning every column, every
  /// CHECK-bounded value, both NULL and non-NULL nullables, every rating enum
  /// value, and child rows in each FK-dependent table.
  private func populateAtV36() async throws -> FixtureIDs {
    try migrator.migrate(appDB.db, upTo: "v36")

    return try await appDB.db.write { db in
      // --- podcasts ---
      try db.execute(
        sql: """
          INSERT INTO podcast (
            id, feedURL, title, image, description, link, lastUpdate,
            subscriptionDate, creationDate, defaultPlaybackRate,
            queueAllEpisodes, cacheAllEpisodes, notifyNewEpisodes, iTunesID
          ) VALUES (
            100, 'https://example.com/full.xml', 'Full Podcast',
            'https://example.com/img.jpg', 'Full description',
            'https://example.com/link',
            '2021-03-15 10:20:30', '2021-03-16 11:22:33',
            '2021-03-15 10:20:30', 2.0, 'always', 'cache', 1, 54321
          )
          """
      )
      try db.execute(
        sql: """
          INSERT INTO podcast (
            id, feedURL, title, image, description, link, lastUpdate,
            subscriptionDate, creationDate, defaultPlaybackRate,
            queueAllEpisodes, cacheAllEpisodes, notifyNewEpisodes, iTunesID
          ) VALUES (
            101, 'https://example.com/minimal.xml', 'Minimal Podcast',
            'https://example.com/min.jpg', '',
            NULL, '2022-06-01 00:00:00', NULL, '2022-05-30 12:00:00',
            NULL, 'never', 'never', 0, NULL
          )
          """
      )

      // --- episodes on podcastFull ---
      try db.execute(
        sql: """
          INSERT INTO episode (
            id, podcastId, guid, mediaURL, title, pubDate, duration, description,
            link, image, finishDate, currentTime, queueOrder, queueDate,
            cachedFilename, downloadTaskID, creationDate, saveInCache,
            maxPlaybackTime, rating, ratingDate
          ) VALUES (
            200, 100, 'guid-full', 'https://example.com/ep-full.mp3',
            'Full Episode', '2021-03-20 08:00:00', 3600, 'Full description text',
            'https://example.com/ep-link', 'https://example.com/ep-img.jpg',
            NULL, 300, 2, '2021-04-01 12:00:00',
            'ep-full.mp3', 9999, '2021-03-20 08:00:00', 1,
            1500, 'loved', '2021-04-02 15:30:00'
          )
          """
      )
      try db.execute(
        sql: """
          INSERT INTO episode (
            id, podcastId, guid, mediaURL, title, pubDate
          ) VALUES (
            201, 100, 'guid-minimal', 'https://example.com/ep-min.mp3',
            'Minimal Episode', '2021-04-01 00:00:00'
          )
          """
      )
      try db.execute(
        sql: """
          INSERT INTO episode (
            id, podcastId, guid, mediaURL, title, pubDate,
            currentTime, queueOrder, rating, ratingDate, saveInCache,
            creationDate, maxPlaybackTime
          ) VALUES (
            202, 100, 'guid-queued', 'https://example.com/ep-q.mp3',
            'Queued Rated', '2021-04-05 00:00:00',
            0, 0, 'disliked', '2021-04-06 09:00:00', 0,
            '2021-04-05 00:00:00', 0
          )
          """
      )
      try db.execute(
        sql: """
          INSERT INTO episode (
            id, podcastId, guid, mediaURL, title, pubDate,
            finishDate, currentTime, cachedFilename, rating, ratingDate,
            saveInCache, creationDate, maxPlaybackTime
          ) VALUES (
            203, 100, 'guid-finished', 'https://example.com/ep-fin.mp3',
            'Finished', '2021-04-10 00:00:00',
            '2021-04-12 14:00:00', 0, 'ep-fin.mp3', 'liked',
            '2021-04-12 14:05:00', 1, '2021-04-10 00:00:00', 2500
          )
          """
      )

      // --- episode on podcastMinimal ---
      try db.execute(
        sql: """
          INSERT INTO episode (
            id, podcastId, guid, mediaURL, title, pubDate,
            creationDate
          ) VALUES (
            204, 101, 'guid-2nd', 'https://example.com/ep-2.mp3',
            'Second Podcast Episode', '2022-06-02 00:00:00',
            '2022-06-02 00:00:00'
          )
          """
      )

      // --- tags + join rows ---
      try db.execute(
        sql: """
          INSERT INTO tag (id, name, creationDate)
          VALUES (300, 'news', '2022-01-01 00:00:00'),
                 (301, 'tech', '2022-01-02 00:00:00')
          """
      )
      try db.execute(
        sql: """
          INSERT INTO podcastTag (podcastId, tagId) VALUES
            (100, 300), (100, 301), (101, 300)
          """
      )
      try db.execute(
        sql: """
          INSERT INTO episodeTag (episodeId, tagId) VALUES
            (200, 300), (200, 301), (203, 300)
          """
      )

      // --- embeddings ---
      let vector = Data([0x01, 0x02, 0x03, 0x04])
      try db.execute(
        sql: """
          INSERT INTO episodeEmbedding (
            episodeId, vector, sourceHash, embeddingRevision, dimension,
            creationDate
          ) VALUES (200, ?, 'hash-200', 1, 3, '2021-04-20 00:00:00')
          """,
        arguments: [vector]
      )
      try db.execute(
        sql: """
          INSERT INTO episodeEmbedding (
            episodeId, vector, sourceHash, embeddingRevision, dimension,
            creationDate
          ) VALUES (203, ?, 'hash-203', 2, 3, '2021-04-20 00:00:00')
          """,
        arguments: [vector]
      )
      try db.execute(
        sql: """
          INSERT INTO podcastEmbedding (
            podcastId, vector, sourceHash, embeddingRevision, dimension,
            creationDate
          ) VALUES (100, ?, 'hash-p100', 1, 3, '2021-04-20 00:00:00')
          """,
        arguments: [vector]
      )

      return FixtureIDs(
        podcastFull: 100,
        podcastMinimal: 101,
        episodeFull: 200,
        episodeMinimal: 201,
        episodeQueuedRated: 202,
        episodeFinished: 203,
        episodeSecondPodcast: 204,
        tagA: 300,
        tagB: 301
      )
    }
  }

  // MARK: - Schema Parity

  @Test("v37 preserves episode schema shape (columns, indexes, FKs) aside from contentUpdatedAt")
  func episodeSchemaParity() async throws {
    _ = try await populateAtV36()
    let before = try await appDB.db.read { try SchemaSnapshot.capture($0, table: "episode") }

    try migrator.migrate(appDB.db, upTo: "v37")
    let after = try await appDB.db.read { try SchemaSnapshot.capture($0, table: "episode") }

    let added = SchemaSnapshot.Column(
      name: "contentUpdatedAt",
      type: "DATETIME",
      notNull: true,
      defaultValue: "CURRENT_TIMESTAMP",
      primaryKeyPosition: 0
    )
    #expect(after.columns == before.columns + [added])
    #expect(after.indexes == before.indexes)
    #expect(after.foreignKeys == before.foreignKeys)
  }

  @Test("v37 preserves podcast schema shape (columns, indexes, FKs) aside from contentUpdatedAt")
  func podcastSchemaParity() async throws {
    _ = try await populateAtV36()
    let before = try await appDB.db.read { try SchemaSnapshot.capture($0, table: "podcast") }

    try migrator.migrate(appDB.db, upTo: "v37")
    let after = try await appDB.db.read { try SchemaSnapshot.capture($0, table: "podcast") }

    let added = SchemaSnapshot.Column(
      name: "contentUpdatedAt",
      type: "DATETIME",
      notNull: true,
      defaultValue: "CURRENT_TIMESTAMP",
      primaryKeyPosition: 0
    )
    #expect(after.columns == before.columns + [added])
    #expect(after.indexes == before.indexes)
    #expect(after.foreignKeys == before.foreignKeys)
  }

  // MARK: - Data Preservation

  @Test("all podcast column values preserved byte-for-byte through v37 rebuild")
  func podcastDataPreserved() async throws {
    _ = try await populateAtV36()

    let preservedColumns = [
      "id", "feedURL", "title", "image", "description", "link",
      "lastUpdate", "subscriptionDate", "creationDate", "defaultPlaybackRate",
      "queueAllEpisodes", "cacheAllEpisodes", "notifyNewEpisodes", "iTunesID",
    ]
    let selectSQL =
      "SELECT \(preservedColumns.joined(separator: ", ")) FROM podcast ORDER BY id"

    let before = try await appDB.db.read { db in
      try Row.fetchAll(db, sql: selectSQL).map { $0.asDictionary() }
    }

    try migrator.migrate(appDB.db, upTo: "v37")

    let after = try await appDB.db.read { db in
      try Row.fetchAll(db, sql: selectSQL).map { $0.asDictionary() }
    }

    #expect(before == after)
  }

  @Test("all episode column values preserved byte-for-byte through v37 rebuild")
  func episodeDataPreserved() async throws {
    _ = try await populateAtV36()

    let preservedColumns = [
      "id", "podcastId", "guid", "mediaURL", "title", "pubDate",
      "duration", "description", "link", "image", "finishDate",
      "currentTime", "queueOrder", "queueDate", "cachedFilename",
      "downloadTaskID", "creationDate", "saveInCache", "maxPlaybackTime",
      "rating", "ratingDate",
    ]
    let selectSQL =
      "SELECT \(preservedColumns.joined(separator: ", ")) FROM episode ORDER BY id"

    let before = try await appDB.db.read { db in
      try Row.fetchAll(db, sql: selectSQL).map { $0.asDictionary() }
    }

    try migrator.migrate(appDB.db, upTo: "v37")

    let after = try await appDB.db.read { db in
      try Row.fetchAll(db, sql: selectSQL).map { $0.asDictionary() }
    }

    #expect(before == after)
  }

  @Test("child tables (embeddings, tag joins) unchanged by v37 rebuild")
  func childTablesPreserved() async throws {
    _ = try await populateAtV36()

    let capture = { [appDB] () async throws -> [String: [[String: DatabaseValue]]] in
      try await appDB.db.read { db in
        [
          "tag": try Row.fetchAll(db, sql: "SELECT * FROM tag ORDER BY id")
            .map { $0.asDictionary() },
          "podcastTag": try Row.fetchAll(
            db, sql: "SELECT * FROM podcastTag ORDER BY podcastId, tagId"
          ).map { $0.asDictionary() },
          "episodeTag": try Row.fetchAll(
            db, sql: "SELECT * FROM episodeTag ORDER BY episodeId, tagId"
          ).map { $0.asDictionary() },
          "episodeEmbedding": try Row.fetchAll(
            db, sql: "SELECT * FROM episodeEmbedding ORDER BY id"
          ).map { $0.asDictionary() },
          "podcastEmbedding": try Row.fetchAll(
            db, sql: "SELECT * FROM podcastEmbedding ORDER BY id"
          ).map { $0.asDictionary() },
        ]
      }
    }

    let before = try await capture()
    try migrator.migrate(appDB.db, upTo: "v37")
    let after = try await capture()

    #expect(before == after)
  }

  // MARK: - Foreign Key Integrity

  @Test("PRAGMA foreign_key_check passes after v37 rebuild")
  func foreignKeyIntegrityAfterRebuild() async throws {
    _ = try await populateAtV36()
    try migrator.migrate(appDB.db, upTo: "v37")

    let violations = try appDB.db.read { db -> [Row] in
      try Row.fetchAll(db, sql: "PRAGMA foreign_key_check")
    }
    #expect(violations.isEmpty)
  }

  @Test("podcast→episode CASCADE delete still wired after v37 rebuild")
  func cascadeStillWorksAfterRebuild() async throws {
    let ids = try await populateAtV36()
    try migrator.migrate(appDB.db, upTo: "v37")

    let episodesBefore = try await appDB.db.read { db in
      try Int.fetchOne(
        db,
        sql: "SELECT COUNT(*) FROM episode WHERE podcastId = ?",
        arguments: [ids.podcastFull]
      ) ?? 0
    }
    #expect(episodesBefore == 4)

    try await appDB.db.write { db in
      try db.execute(
        sql: "DELETE FROM podcast WHERE id = ?",
        arguments: [ids.podcastFull]
      )
    }

    try await appDB.db.read { db in
      let remaining = try Int.fetchOne(
        db,
        sql: "SELECT COUNT(*) FROM episode WHERE podcastId = ?",
        arguments: [ids.podcastFull]
      ) ?? -1
      #expect(remaining == 0)

      // Episodes on the other podcast are untouched.
      let survivors = try Int.fetchOne(
        db,
        sql: "SELECT COUNT(*) FROM episode WHERE podcastId = ?",
        arguments: [ids.podcastMinimal]
      ) ?? -1
      #expect(survivors == 1)
    }
  }

  @Test("episode→podcast CASCADE also cleans tag-join rows after rebuild")
  func tagJoinsCleanedByCascade() async throws {
    let ids = try await populateAtV36()
    try migrator.migrate(appDB.db, upTo: "v37")

    try await appDB.db.write { db in
      try db.execute(
        sql: "DELETE FROM podcast WHERE id = ?",
        arguments: [ids.podcastFull]
      )
    }

    let remainingPodcastTags = try await appDB.db.read { db in
      try Int.fetchOne(
        db,
        sql: "SELECT COUNT(*) FROM podcastTag WHERE podcastId = ?",
        arguments: [ids.podcastFull]
      ) ?? -1
    }
    let remainingEpisodeTags = try await appDB.db.read { db in
      try Int.fetchOne(
        db,
        sql: "SELECT COUNT(*) FROM episodeTag WHERE episodeId = ?",
        arguments: [ids.episodeFull]
      ) ?? -1
    }
    #expect(remainingPodcastTags == 0)
    #expect(remainingEpisodeTags == 0)
  }

  // MARK: - AUTOINCREMENT

  @Test("episode AUTOINCREMENT continues from max id after v37 rebuild")
  func episodeAutoincrementContinues() async throws {
    let ids = try await populateAtV36()
    try migrator.migrate(appDB.db, upTo: "v37")

    let newID = try await appDB.db.write { db in
      try db.execute(
        sql: """
          INSERT INTO episode (podcastId, guid, mediaURL, title, pubDate)
          VALUES (?, 'guid-post', 'https://example.com/post.mp3', 'Post', ?)
          """,
        arguments: [ids.podcastMinimal, "2023-01-01 00:00:00"]
      )
      return db.lastInsertedRowID
    }
    // Max existing id was 204.
    #expect(newID == 205)
  }

  @Test("podcast AUTOINCREMENT continues from max id after v37 rebuild")
  func podcastAutoincrementContinues() async throws {
    _ = try await populateAtV36()
    try migrator.migrate(appDB.db, upTo: "v37")

    let newID = try await appDB.db.write { db in
      try db.execute(
        sql: """
          INSERT INTO podcast (feedURL, title, image, description)
          VALUES ('https://example.com/post.xml', 'Post', 'img', 'desc')
          """
      )
      return db.lastInsertedRowID
    }
    // Max existing id was 101.
    #expect(newID == 102)
  }

  // MARK: - Constraint Enforcement

  @Test("episode (podcastId, guid) UNIQUE still enforced after v37 rebuild")
  func episodeCompoundUniquePodcastGuid() async throws {
    let ids = try await populateAtV36()
    try migrator.migrate(appDB.db, upTo: "v37")

    await #expect(throws: DatabaseError.self) {
      try await self.appDB.db.write { db in
        try db.execute(
          sql: """
            INSERT INTO episode (podcastId, guid, mediaURL, title, pubDate)
            VALUES (?, 'guid-full', 'https://example.com/different.mp3', 'Dup', ?)
            """,
          arguments: [ids.podcastFull, "2023-01-01 00:00:00"]
        )
      }
    }
  }

  @Test("episode (podcastId, mediaURL) UNIQUE still enforced after v37 rebuild")
  func episodeCompoundUniquePodcastMediaURL() async throws {
    let ids = try await populateAtV36()
    try migrator.migrate(appDB.db, upTo: "v37")

    await #expect(throws: DatabaseError.self) {
      try await self.appDB.db.write { db in
        try db.execute(
          sql: """
            INSERT INTO episode (podcastId, guid, mediaURL, title, pubDate)
            VALUES (?, 'guid-different', 'https://example.com/ep-full.mp3', 'Dup', ?)
            """,
          arguments: [ids.podcastFull, "2023-01-01 00:00:00"]
        )
      }
    }
  }

  @Test("episode (guid, mediaURL) UNIQUE still enforced after v37 rebuild")
  func episodeCompoundUniqueGuidMediaURL() async throws {
    let ids = try await populateAtV36()
    try migrator.migrate(appDB.db, upTo: "v37")

    await #expect(throws: DatabaseError.self) {
      try await self.appDB.db.write { db in
        try db.execute(
          sql: """
            INSERT INTO episode (podcastId, guid, mediaURL, title, pubDate)
            VALUES (?, 'guid-full', 'https://example.com/ep-full.mp3', 'Dup', ?)
            """,
          arguments: [ids.podcastMinimal, "2023-01-01 00:00:00"]
        )
      }
    }
  }

  @Test("episode downloadTaskID UNIQUE still enforced after v37 rebuild")
  func episodeDownloadTaskIDUnique() async throws {
    let ids = try await populateAtV36()
    try migrator.migrate(appDB.db, upTo: "v37")

    await #expect(throws: DatabaseError.self) {
      try await self.appDB.db.write { db in
        try db.execute(
          sql: """
            INSERT INTO episode (
              podcastId, guid, mediaURL, title, pubDate, downloadTaskID
            ) VALUES (?, 'guid-dl', 'https://example.com/dl.mp3', 'Dup DL', ?, 9999)
            """,
          arguments: [ids.podcastMinimal, "2023-01-01 00:00:00"]
        )
      }
    }
  }

  @Test("podcast feedURL UNIQUE still enforced after v37 rebuild")
  func podcastFeedURLUnique() async throws {
    _ = try await populateAtV36()
    try migrator.migrate(appDB.db, upTo: "v37")

    await #expect(throws: DatabaseError.self) {
      try await self.appDB.db.write { db in
        try db.execute(
          sql: """
            INSERT INTO podcast (feedURL, title, image, description)
            VALUES ('https://example.com/full.xml', 'Dup', 'img', 'desc')
            """
        )
      }
    }
  }

  @Test("podcast iTunesID UNIQUE still enforced after v37 rebuild")
  func podcastITunesIDUnique() async throws {
    _ = try await populateAtV36()
    try migrator.migrate(appDB.db, upTo: "v37")

    await #expect(throws: DatabaseError.self) {
      try await self.appDB.db.write { db in
        try db.execute(
          sql: """
            INSERT INTO podcast (feedURL, title, image, description, iTunesID)
            VALUES ('https://example.com/dup-itunes.xml', 'Dup', 'img', 'desc', 54321)
            """
        )
      }
    }
  }

  @Test("episode queueOrder CHECK still rejects negative values after rebuild")
  func queueOrderCheckEnforced() async throws {
    let ids = try await populateAtV36()
    try migrator.migrate(appDB.db, upTo: "v37")

    await #expect(throws: DatabaseError.self) {
      try await self.appDB.db.write { db in
        try db.execute(
          sql: """
            INSERT INTO episode (podcastId, guid, mediaURL, title, pubDate, queueOrder)
            VALUES (?, 'guid-neg', 'https://example.com/neg.mp3', 'Neg', ?, -1)
            """,
          arguments: [ids.podcastMinimal, "2023-01-01 00:00:00"]
        )
      }
    }
  }

  @Test("episode rating CHECK still rejects invalid values after rebuild")
  func ratingCheckEnforced() async throws {
    let ids = try await populateAtV36()
    try migrator.migrate(appDB.db, upTo: "v37")

    await #expect(throws: DatabaseError.self) {
      try await self.appDB.db.write { db in
        try db.execute(
          sql: """
            INSERT INTO episode (podcastId, guid, mediaURL, title, pubDate, rating)
            VALUES (?, 'guid-bad', 'https://example.com/bad.mp3', 'Bad', ?, 'hated')
            """,
          arguments: [ids.podcastMinimal, "2023-01-01 00:00:00"]
        )
      }
    }
  }

  @Test("podcast defaultPlaybackRate CHECK still rejects out-of-range values after rebuild")
  func playbackRateCheckEnforced() async throws {
    _ = try await populateAtV36()
    try migrator.migrate(appDB.db, upTo: "v37")

    await #expect(throws: DatabaseError.self) {
      try await self.appDB.db.write { db in
        try db.execute(
          sql: """
            INSERT INTO podcast (
              feedURL, title, image, description, defaultPlaybackRate
            ) VALUES ('https://example.com/fast.xml', 'Fast', 'img', 'desc', 3.0)
            """
        )
      }
    }
  }

  // MARK: - contentUpdatedAt Backfill & Default

  @Test("existing rows get contentUpdatedAt backfilled from creationDate")
  func backfillFromCreationDate() async throws {
    let ids = try await populateAtV36()
    try migrator.migrate(appDB.db, upTo: "v37")

    try await appDB.db.read { db in
      let epFullUpdated = try String.fetchOne(
        db,
        sql: "SELECT contentUpdatedAt FROM episode WHERE id = ?",
        arguments: [ids.episodeFull]
      )
      #expect(epFullUpdated == "2021-03-20 08:00:00")

      let epMinUpdated = try String.fetchOne(
        db,
        sql: "SELECT contentUpdatedAt FROM episode WHERE id = ?",
        arguments: [ids.episodeMinimal]
      )
      // episodeMinimal omitted creationDate, so it was set by CURRENT_TIMESTAMP
      // at insert. Assert only that backfill produced a non-NULL equal to
      // creationDate (not that it equals any specific fixed string).
      let epMinCreation = try String.fetchOne(
        db,
        sql: "SELECT creationDate FROM episode WHERE id = ?",
        arguments: [ids.episodeMinimal]
      )
      #expect(epMinUpdated != nil)
      #expect(epMinUpdated == epMinCreation)

      let pcFullUpdated = try String.fetchOne(
        db,
        sql: "SELECT contentUpdatedAt FROM podcast WHERE id = ?",
        arguments: [ids.podcastFull]
      )
      #expect(pcFullUpdated == "2021-03-15 10:20:30")

      let pcMinUpdated = try String.fetchOne(
        db,
        sql: "SELECT contentUpdatedAt FROM podcast WHERE id = ?",
        arguments: [ids.podcastMinimal]
      )
      #expect(pcMinUpdated == "2022-05-30 12:00:00")
    }
  }

  @Test("new inserts without explicit contentUpdatedAt get CURRENT_TIMESTAMP default")
  func defaultCurrentTimestampOnInsert() async throws {
    let ids = try await populateAtV36()
    try migrator.migrate(appDB.db, upTo: "v37")

    try await appDB.db.write { db in
      try db.execute(
        sql: """
          INSERT INTO episode (podcastId, guid, mediaURL, title, pubDate)
          VALUES (?, 'guid-post', 'https://example.com/post.mp3', 'Post', ?)
          """,
        arguments: [ids.podcastMinimal, "2023-01-01 00:00:00"]
      )
      let newID = db.lastInsertedRowID
      let value = try String.fetchOne(
        db,
        sql: "SELECT contentUpdatedAt FROM episode WHERE id = ?",
        arguments: [newID]
      )
      #expect(value != nil)
    }
  }

  // MARK: - Triggers

  @Test("episode_content_updated fires when title changes")
  func episodeTitleTriggerFires() async throws {
    let ids = try await populateAtV36()
    try migrator.migrate(appDB.db, upTo: "v37")

    let before = try await appDB.db.read { db in
      try String.fetchOne(
        db,
        sql: "SELECT contentUpdatedAt FROM episode WHERE id = ?",
        arguments: [ids.episodeFull]
      )
    }

    try await appDB.db.write { db in
      try db.execute(
        sql: "UPDATE episode SET title = ? WHERE id = ?",
        arguments: ["Retitled", ids.episodeFull]
      )
    }

    let after = try await appDB.db.read { db in
      try String.fetchOne(
        db,
        sql: "SELECT contentUpdatedAt FROM episode WHERE id = ?",
        arguments: [ids.episodeFull]
      )
    }
    #expect(after != before)
    #expect((after ?? "") > (before ?? ""))
  }

  @Test("episode_content_updated fires when description changes")
  func episodeDescriptionTriggerFires() async throws {
    let ids = try await populateAtV36()
    try migrator.migrate(appDB.db, upTo: "v37")

    let before = try await appDB.db.read { db in
      try String.fetchOne(
        db,
        sql: "SELECT contentUpdatedAt FROM episode WHERE id = ?",
        arguments: [ids.episodeFull]
      )
    }

    try await appDB.db.write { db in
      try db.execute(
        sql: "UPDATE episode SET description = ? WHERE id = ?",
        arguments: ["Rewritten", ids.episodeFull]
      )
    }

    let after = try await appDB.db.read { db in
      try String.fetchOne(
        db,
        sql: "SELECT contentUpdatedAt FROM episode WHERE id = ?",
        arguments: [ids.episodeFull]
      )
    }
    #expect(after != before)
  }

  @Test("episode_content_updated does NOT fire on non-content column changes")
  func episodeTriggerIgnoresNonContent() async throws {
    let ids = try await populateAtV36()
    try migrator.migrate(appDB.db, upTo: "v37")

    let before = try await appDB.db.read { db in
      try String.fetchOne(
        db,
        sql: "SELECT contentUpdatedAt FROM episode WHERE id = ?",
        arguments: [ids.episodeFull]
      )
    }

    try await appDB.db.write { db in
      try db.execute(
        sql: "UPDATE episode SET currentTime = currentTime + 1 WHERE id = ?",
        arguments: [ids.episodeFull]
      )
    }

    let after = try await appDB.db.read { db in
      try String.fetchOne(
        db,
        sql: "SELECT contentUpdatedAt FROM episode WHERE id = ?",
        arguments: [ids.episodeFull]
      )
    }
    #expect(after == before)
  }

  @Test("podcast_content_updated fires when description changes")
  func podcastDescriptionTriggerFires() async throws {
    let ids = try await populateAtV36()
    try migrator.migrate(appDB.db, upTo: "v37")

    let before = try await appDB.db.read { db in
      try String.fetchOne(
        db,
        sql: "SELECT contentUpdatedAt FROM podcast WHERE id = ?",
        arguments: [ids.podcastFull]
      )
    }

    try await appDB.db.write { db in
      try db.execute(
        sql: "UPDATE podcast SET description = ? WHERE id = ?",
        arguments: ["Rewritten podcast description", ids.podcastFull]
      )
    }

    let after = try await appDB.db.read { db in
      try String.fetchOne(
        db,
        sql: "SELECT contentUpdatedAt FROM podcast WHERE id = ?",
        arguments: [ids.podcastFull]
      )
    }
    #expect(after != before)
  }

  @Test("podcast_content_updated does NOT fire on non-description changes")
  func podcastTriggerIgnoresNonDescription() async throws {
    let ids = try await populateAtV36()
    try migrator.migrate(appDB.db, upTo: "v37")

    let before = try await appDB.db.read { db in
      try String.fetchOne(
        db,
        sql: "SELECT contentUpdatedAt FROM podcast WHERE id = ?",
        arguments: [ids.podcastFull]
      )
    }

    try await appDB.db.write { db in
      try db.execute(
        sql: "UPDATE podcast SET lastUpdate = ? WHERE id = ?",
        arguments: ["2099-01-01 00:00:00", ids.podcastFull]
      )
    }

    let after = try await appDB.db.read { db in
      try String.fetchOne(
        db,
        sql: "SELECT contentUpdatedAt FROM podcast WHERE id = ?",
        arguments: [ids.podcastFull]
      )
    }
    #expect(after == before)
  }
}

// MARK: - Schema introspection helper

private struct SchemaSnapshot: Equatable {
  struct Column: Equatable {
    let name: String
    let type: String
    let notNull: Bool
    let defaultValue: String?
    let primaryKeyPosition: Int
  }

  struct Index: Equatable, Comparable {
    let columns: [String]
    let unique: Bool
    let partial: Bool

    static func < (lhs: Index, rhs: Index) -> Bool {
      if lhs.columns != rhs.columns {
        return lhs.columns.joined(separator: ",") < rhs.columns.joined(separator: ",")
      }
      if lhs.unique != rhs.unique { return !lhs.unique }
      return !lhs.partial && rhs.partial
    }
  }

  struct ForeignKey: Equatable, Comparable {
    let table: String
    let from: String
    let to: String
    let onDelete: String
    let onUpdate: String

    static func < (lhs: ForeignKey, rhs: ForeignKey) -> Bool {
      (lhs.table, lhs.from, lhs.to) < (rhs.table, rhs.from, rhs.to)
    }
  }

  let columns: [Column]
  let indexes: [Index]
  let foreignKeys: [ForeignKey]

  static func capture(_ db: Database, table: String) throws -> SchemaSnapshot {
    let tableInfo = try Row.fetchAll(db, sql: "PRAGMA table_info(\(table))")
    let columns: [Column] = tableInfo.map { row in
      Column(
        name: row["name"] as? String ?? "",
        type: row["type"] as? String ?? "",
        notNull: (row["notnull"] as? Int64 ?? 0) != 0,
        defaultValue: row["dflt_value"] as? String,
        primaryKeyPosition: Int(row["pk"] as? Int64 ?? 0)
      )
    }

    let indexList = try Row.fetchAll(db, sql: "PRAGMA index_list(\(table))")
    let indexes: [Index] = try indexList.map { row in
      let name = row["name"] as? String ?? ""
      let unique = (row["unique"] as? Int64 ?? 0) != 0
      let partial = (row["partial"] as? Int64 ?? 0) != 0
      let indexInfo = try Row.fetchAll(db, sql: "PRAGMA index_info(\(name))")
      // seqno column gives column order within the index.
      let ordered =
        indexInfo
        .sorted { ($0["seqno"] as? Int64 ?? 0) < ($1["seqno"] as? Int64 ?? 0) }
        .map { $0["name"] as? String ?? "" }
      return Index(columns: ordered, unique: unique, partial: partial)
    }

    let fkList = try Row.fetchAll(db, sql: "PRAGMA foreign_key_list(\(table))")
    let foreignKeys: [ForeignKey] = fkList.map { row in
      ForeignKey(
        table: row["table"] as? String ?? "",
        from: row["from"] as? String ?? "",
        to: row["to"] as? String ?? "",
        onDelete: row["on_delete"] as? String ?? "",
        onUpdate: row["on_update"] as? String ?? ""
      )
    }

    // Compare indexes and FKs as sorted sets — SQLite may report them in a
    // different order after the rebuild even when the semantics match.
    return SchemaSnapshot(
      columns: columns,
      indexes: indexes.sorted(),
      foreignKeys: foreignKeys.sorted()
    )
  }
}

// MARK: - Row dictionary helper

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
