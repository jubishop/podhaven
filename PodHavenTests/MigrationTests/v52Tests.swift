// Copyright Justin Bishop, 2026

import Foundation
import GRDB
import Testing

@testable import PodHaven

@Suite("of v52 migration tests", .container)
class V52MigrationTests {
  private let appDB = AppDB.inMemory(migrate: false)
  private let migrator: DatabaseMigrator

  init() async throws {
    self.migrator = Schema.makeMigrator()
  }

  // MARK: - Fixture

  // Seed at v51 with one podcast and two episodes — one in progress, one
  // untouched — so the backfill has both branches to cover.
  private func populateAtV51() async throws {
    try migrator.migrate(appDB.unsafeTestDB, upTo: "v51")

    try await appDB.unsafeTestDB.write { db in
      try db.execute(
        sql: """
          INSERT INTO podcast (
            id, feedURL, title, image, description, link, lastUpdate,
            subscriptionDate, creationDate, defaultPlaybackRate,
            queueAllEpisodes, cacheAllEpisodes, notifyNewEpisodes, iTunesID,
            contentUpdatedAt
          ) VALUES (
            600, 'https://example.com/v52.xml', 'V52 Podcast',
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
            610, 600, 'guid-1', 'https://example.com/ep1.mp3',
            'In Progress', '2024-02-01 00:00:00', '2024-02-01 00:00:00',
            '2024-02-01 00:00:00', 123.5, 123.5, 0, 0
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
            611, 600, 'guid-2', 'https://example.com/ep2.mp3',
            'Untouched', '2024-02-02 00:00:00', '2024-02-02 00:00:00',
            '2024-02-02 00:00:00', 0, 0, 0, 0
          )
          """
      )
    }
  }

  // MARK: - Column Addition

  @Test("v52 adds a NOT NULL playbackStarted column defaulting to false")
  func addsPlaybackStartedColumn() async throws {
    try await populateAtV51()

    let before = try await appDB.unsafeTestDB.read { db in
      try Row.fetchAll(db, sql: "PRAGMA table_info(episode)")
        .map { $0["name"] as String }
    }
    #expect(!before.contains("playbackStarted"))

    try migrator.migrate(appDB.unsafeTestDB, upTo: "v52")

    let column: (notNull: Int64, defaultValue: String)? = try await appDB.unsafeTestDB.read {
      db in
      guard
        let row = try Row.fetchAll(db, sql: "PRAGMA table_info(episode)")
          .first(where: { $0["name"] as String == "playbackStarted" })
      else { return nil }
      return (row["notnull"] as Int64, row["dflt_value"] as String)
    }
    let info = try #require(column)
    #expect(info.notNull == 1)
    #expect(info.defaultValue == "0")
  }

  // MARK: - Backfill

  @Test("v52 backfills playbackStarted from currentTime > 0")
  func backfillsFromCurrentTime() async throws {
    try await populateAtV51()
    try migrator.migrate(appDB.unsafeTestDB, upTo: "v52")

    let flags = try await appDB.unsafeTestDB.read { db in
      try Row.fetchAll(
        db,
        sql: "SELECT id, playbackStarted FROM episode ORDER BY id"
      )
      .map { ($0["id"] as Int64, $0["playbackStarted"] as Bool) }
    }
    #expect(flags.count == 2)
    #expect(flags[0] == (610, true))
    #expect(flags[1] == (611, false))
  }
}
