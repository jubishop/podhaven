// Copyright Justin Bishop, 2026

import Foundation
import GRDB
import Testing

@testable import PodHaven

@Suite("of v51 migration tests", .container)
class V51MigrationTests {
  private let appDB = AppDB.inMemory(migrate: false)
  private let migrator: DatabaseMigrator

  init() async throws {
    self.migrator = Schema.makeMigrator()
  }

  // MARK: - Fixture

  // Seed at v50 with one podcast and two episodes — one rated, one not — so the
  // partial rating index and the migrated data both have something to cover.
  private func populateAtV50() async throws {
    try migrator.migrate(appDB.unsafeTestDB, upTo: "v50")

    try await appDB.unsafeTestDB.write { db in
      try db.execute(
        sql: """
          INSERT INTO podcast (
            id, feedURL, title, image, description, link, lastUpdate,
            subscriptionDate, creationDate, defaultPlaybackRate,
            queueAllEpisodes, cacheAllEpisodes, notifyNewEpisodes, iTunesID,
            contentUpdatedAt
          ) VALUES (
            500, 'https://example.com/v51.xml', 'V51 Podcast',
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
            downloading, rating, ratingDate
          ) VALUES (
            510, 500, 'guid-1', 'https://example.com/ep1.mp3',
            'Rated', '2024-02-01 00:00:00', '2024-02-01 00:00:00',
            '2024-02-01 00:00:00', 0, 0, 0, 0, 'loved', '2024-02-01 00:00:00'
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
            511, 500, 'guid-2', 'https://example.com/ep2.mp3',
            'Unrated', '2024-02-02 00:00:00', '2024-02-02 00:00:00',
            '2024-02-02 00:00:00', 0, 0, 0, 0
          )
          """
      )
    }
  }

  private func indexNames(on table: String) async throws -> Set<String> {
    try await appDB.unsafeTestDB.read { db in
      Set(
        try Row.fetchAll(
          db,
          sql: "SELECT name FROM sqlite_master WHERE type = 'index' AND tbl_name = ?",
          arguments: [table]
        )
        .map { $0["name"] as String }
      )
    }
  }

  // MARK: - Index Changes

  @Test("v51 replaces the standalone podcastId index with the (podcastId, pubDate) composite")
  func replacesPodcastIdIndex() async throws {
    try await populateAtV50()

    let before = try await indexNames(on: "episode")
    #expect(before.contains("episode_on_podcastId"))
    #expect(!before.contains("episode_on_podcastId_pubDate"))

    try migrator.migrate(appDB.unsafeTestDB, upTo: "v51")

    let after = try await indexNames(on: "episode")
    #expect(!after.contains("episode_on_podcastId"))
    #expect(after.contains("episode_on_podcastId_pubDate"))
  }

  @Test("v51 adds the contentUpdatedAt and partial rating indexes")
  func addsSignalAndRatingIndexes() async throws {
    try await populateAtV50()
    try migrator.migrate(appDB.unsafeTestDB, upTo: "v51")

    let episodeIndexes = try await indexNames(on: "episode")
    #expect(episodeIndexes.contains("episode_on_contentUpdatedAt"))
    #expect(episodeIndexes.contains("episode_on_rating"))

    let podcastIndexes = try await indexNames(on: "podcast")
    #expect(podcastIndexes.contains("podcast_on_contentUpdatedAt"))

    // The rating index is partial so it only carries the rated rows.
    let ratingIndexSQL = try await appDB.unsafeTestDB.read { db in
      try String.fetchOne(
        db,
        sql: "SELECT sql FROM sqlite_master WHERE name = 'episode_on_rating'"
      )
    }
    #expect(ratingIndexSQL?.contains("WHERE") == true)
  }

  // MARK: - Data Preservation

  @Test("v51 leaves existing episode rows intact")
  func preservesEpisodes() async throws {
    try await populateAtV50()
    try migrator.migrate(appDB.unsafeTestDB, upTo: "v51")

    let ids = try await appDB.unsafeTestDB.read { db in
      try Int.fetchAll(db, sql: "SELECT id FROM episode ORDER BY id")
    }
    #expect(ids == [510, 511])
  }
}
