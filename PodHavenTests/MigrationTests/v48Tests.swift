// Copyright Justin Bishop, 2026

import Foundation
import GRDB
import Testing

@testable import PodHaven

@Suite("of v48 migration tests", .container)
class V48MigrationTests {
  private let appDB = AppDB.inMemory(migrate: false)
  private let migrator: DatabaseMigrator

  init() async throws {
    self.migrator = Schema.makeMigrator()
  }

  // MARK: - Fixture

  // Seed one podcast at v47 — the last schema before the FTS migration — and
  // return its id so episodes can hang off it.
  private func seedPodcastAtV47(
    title: String = "Tech Talk",
    description: String = "Conversations about technology"
  ) async throws -> Int64 {
    try migrator.migrate(appDB.unsafeTestDB, upTo: "v47")
    return try await appDB.unsafeTestDB.write { db in
      try db.execute(
        sql: """
          INSERT INTO podcast (feedURL, title, image, description)
          VALUES (?, ?, 'img', ?)
          """,
        arguments: ["https://example.com/feed.xml", title, description]
      )
      return db.lastInsertedRowID
    }
  }

  private func insertEpisode(
    podcastId: Int64,
    guid: String,
    title: String,
    description: String
  ) async throws -> Int64 {
    try await appDB.unsafeTestDB.write { db in
      try db.execute(
        sql: """
          INSERT INTO episode (podcastId, guid, mediaURL, title, pubDate, description)
          VALUES (?, ?, ?, ?, '2025-01-01 00:00:00', ?)
          """,
        arguments: [podcastId, guid, "https://example.com/\(guid).mp3", title, description]
      )
      return db.lastInsertedRowID
    }
  }

  // The FTS mirror's rowid equals its source row's id, so the ids returned here
  // are episode/podcast ids — exactly what `Episode.matchesText` joins back on.
  private func ftsMatches(_ table: String, _ term: String) async throws -> [Int64] {
    try await appDB.unsafeTestDB.read { db in
      try Int64.fetchAll(
        db,
        sql: "SELECT rowid FROM \(table) WHERE \(table) MATCH ? ORDER BY rowid",
        arguments: [term]
      )
    }
  }

  // MARK: - Tables Created

  @Test("v48 creates the episode_fts and podcast_fts virtual tables")
  func virtualTablesCreated() async throws {
    try migrator.migrate(appDB.unsafeTestDB, upTo: "v47")

    try await appDB.unsafeTestDB.read { db in
      let before = try String.fetchAll(
        db,
        sql: "SELECT name FROM sqlite_master WHERE name IN ('episode_fts', 'podcast_fts')"
      )
      #expect(before.isEmpty)
    }

    try migrator.migrate(appDB.unsafeTestDB, upTo: "v48")

    try await appDB.unsafeTestDB.read { db in
      let after = Set(
        try String.fetchAll(
          db,
          sql: "SELECT name FROM sqlite_master WHERE name IN ('episode_fts', 'podcast_fts')"
        )
      )
      #expect(after == ["episode_fts", "podcast_fts"])
    }
  }

  // MARK: - Backfill

  // synchronize(withTable:) seeds the mirror with rows that already existed when
  // the migration ran. Rows inserted on a fully-migrated DB never exercise this
  // path, so prove the initial population here.
  @Test("v48 backfills pre-existing episodes into episode_fts keyed by id")
  func episodeBackfill() async throws {
    let podcastId = try await seedPodcastAtV47()
    let swiftID = try await insertEpisode(
      podcastId: podcastId,
      guid: "swift",
      title: "Swift Concurrency",
      description: "Tasks and actors"
    )
    let rustID = try await insertEpisode(
      podcastId: podcastId,
      guid: "rust",
      title: "Rust Ownership",
      description: "Borrows and lifetimes"
    )

    try migrator.migrate(appDB.unsafeTestDB, upTo: "v48")

    #expect(try await ftsMatches("episode_fts", "concurrency") == [swiftID])
    #expect(try await ftsMatches("episode_fts", "lifetimes") == [rustID])
    // The description column is indexed too, not just the title.
    #expect(try await ftsMatches("episode_fts", "actors") == [swiftID])
  }

  @Test("v48 backfills pre-existing podcasts into podcast_fts keyed by id")
  func podcastBackfill() async throws {
    let podcastId = try await seedPodcastAtV47(
      title: "Astronomy Weekly",
      description: "Stars and galaxies"
    )

    try migrator.migrate(appDB.unsafeTestDB, upTo: "v48")

    #expect(try await ftsMatches("podcast_fts", "astronomy") == [podcastId])
    #expect(try await ftsMatches("podcast_fts", "galaxies") == [podcastId])
  }

  // MARK: - Trigger Sync

  @Test("episode_fts tracks inserts, updates, and deletes after v48")
  func episodeTriggersStayInSync() async throws {
    let podcastId = try await seedPodcastAtV47()
    try migrator.migrate(appDB.unsafeTestDB, upTo: "v48")

    // INSERT after the migration is indexed by the synchronize triggers.
    let id = try await insertEpisode(
      podcastId: podcastId,
      guid: "ep1",
      title: "Quantum Computing",
      description: "Qubits explained"
    )
    #expect(try await ftsMatches("episode_fts", "quantum") == [id])

    // UPDATE re-indexes: the old term drops out, the new term matches.
    try await appDB.unsafeTestDB.write { db in
      try db.execute(
        sql: "UPDATE episode SET title = 'Classical Computing' WHERE id = ?",
        arguments: [id]
      )
    }
    #expect(try await ftsMatches("episode_fts", "quantum").isEmpty)
    #expect(try await ftsMatches("episode_fts", "classical") == [id])

    // DELETE removes the row from the index.
    try await appDB.unsafeTestDB.write { db in
      try db.execute(sql: "DELETE FROM episode WHERE id = ?", arguments: [id])
    }
    #expect(try await ftsMatches("episode_fts", "classical").isEmpty)
  }

  @Test("podcast_fts tracks updates and deletes after v48")
  func podcastTriggersStayInSync() async throws {
    let podcastId = try await seedPodcastAtV47(
      title: "Astronomy Weekly",
      description: "Stars and galaxies"
    )
    try migrator.migrate(appDB.unsafeTestDB, upTo: "v48")

    try await appDB.unsafeTestDB.write { db in
      try db.execute(
        sql: "UPDATE podcast SET title = 'Geology Weekly' WHERE id = ?",
        arguments: [podcastId]
      )
    }
    #expect(try await ftsMatches("podcast_fts", "astronomy").isEmpty)
    #expect(try await ftsMatches("podcast_fts", "geology") == [podcastId])

    try await appDB.unsafeTestDB.write { db in
      try db.execute(sql: "DELETE FROM podcast WHERE id = ?", arguments: [podcastId])
    }
    #expect(try await ftsMatches("podcast_fts", "geology").isEmpty)
  }
}
