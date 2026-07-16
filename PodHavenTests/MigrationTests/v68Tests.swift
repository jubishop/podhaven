// Copyright Justin Bishop, 2026

import GRDB
import Testing

@testable import PodHaven

@Suite("of v68 migration tests", .container)
struct V68MigrationTests {
  private static let contentTimestamp = "2040-01-01 00:00:00.750"
  private static let verificationTimestamp = "2040-01-01 00:00:00.500"

  private let appDB = AppDB.inMemory(migrate: false)
  private let migrator: DatabaseMigrator

  init() async throws {
    self.migrator = Schema.makeMigrator()
  }

  private func prepareFixture() async throws {
    try migrator.migrate(appDB.unsafeTestDB, upTo: "v67")
    try await appDB.unsafeTestDB.write { db in
      db.add(
        function: DatabaseFunction("STRFTIME", argumentCount: 2, pure: true) { _ in
          Self.contentTimestamp
        }
      )
      try db.execute(
        sql: """
          INSERT INTO podcast (
            id, feedURL, title, image, description, link, lastUpdate,
            subscriptionDate, creationDate, defaultPlaybackRate,
            queueAllEpisodes, cacheAllEpisodes, notifyNewEpisodes, iTunesID,
            contentUpdatedAt
          ) VALUES (
            800, 'https://example.com/v68.xml', 'Original Podcast',
            'https://example.com/img.jpg', 'Description', NULL,
            '2024-01-01 00:00:00', NULL, '2024-01-01 00:00:00',
            1.0, 'never', 'never', 0, NULL, '2024-01-01 00:00:00'
          )
          """
      )
      try db.execute(
        sql: """
          INSERT INTO episode (
            id, podcastId, guid, mediaURL, title, pubDate, description,
            creationDate, contentUpdatedAt
          ) VALUES (
            801, 800, 'v68-episode', 'https://example.com/v68.mp3',
            'Original Episode', '2024-01-01 00:00:00', 'Description',
            '2024-01-01 00:00:00', '2024-01-01 00:00:00'
          )
          """
      )
      try db.execute(
        sql: """
          INSERT INTO episodeEmbedding (
            episodeId, vector, sourceHash, embeddingRevision, dimension,
            creationDate, verificationDate
          ) VALUES (
            801, zeroblob(12), 'same-revision', 1, 3,
            ?, ?
          )
          """,
        arguments: [Self.verificationTimestamp, Self.verificationTimestamp]
      )
    }

    try migrator.migrate(appDB.unsafeTestDB)
  }

  @Test("v68 keeps same-second episode edits newer than embedding verification")
  func episodeEditsRemainNewerThanVerification() async throws {
    try await prepareFixture()
    try await appDB.unsafeTestDB.write { db in
      try db.execute(sql: "UPDATE episode SET title = 'Updated Episode' WHERE id = 801")
    }

    try await appDB.unsafeTestDB.read { db in
      let contentUpdatedAt = try String.fetchOne(
        db,
        sql: "SELECT contentUpdatedAt FROM episode WHERE id = 801"
      )
      #expect(contentUpdatedAt == Self.contentTimestamp)

      let staleEpisodeIDs = try Int64.fetchAll(
        db,
        sql: """
          SELECT episode.id
          FROM episode
          JOIN episodeEmbedding ON episodeEmbedding.episodeId = episode.id
          WHERE episode.contentUpdatedAt > episodeEmbedding.verificationDate
          """
      )
      #expect(staleEpisodeIDs == [801])

      let oldFTSMatches = try Int64.fetchAll(
        db,
        sql: "SELECT rowid FROM episode_fts WHERE episode_fts MATCH 'Original'"
      )
      #expect(oldFTSMatches.isEmpty)
      let newFTSMatches = try Int64.fetchAll(
        db,
        sql: "SELECT rowid FROM episode_fts WHERE episode_fts MATCH 'Updated'"
      )
      #expect(newFTSMatches == [801])
    }
  }

  @Test("v68 keeps same-second podcast edits newer than embedding verification")
  func podcastEditsRemainNewerThanVerification() async throws {
    try await prepareFixture()
    try await appDB.unsafeTestDB.write { db in
      try db.execute(sql: "UPDATE podcast SET title = 'Updated Podcast' WHERE id = 800")
    }

    try await appDB.unsafeTestDB.read { db in
      let contentUpdatedAt = try String.fetchOne(
        db,
        sql: "SELECT contentUpdatedAt FROM podcast WHERE id = 800"
      )
      #expect(contentUpdatedAt == Self.contentTimestamp)

      let staleEpisodeIDs = try Int64.fetchAll(
        db,
        sql: """
          SELECT episode.id
          FROM episode
          JOIN podcast ON podcast.id = episode.podcastId
          JOIN episodeEmbedding ON episodeEmbedding.episodeId = episode.id
          WHERE podcast.contentUpdatedAt > episodeEmbedding.verificationDate
          """
      )
      #expect(staleEpisodeIDs == [801])

      let oldFTSMatches = try Int64.fetchAll(
        db,
        sql: "SELECT rowid FROM podcast_fts WHERE podcast_fts MATCH 'Original'"
      )
      #expect(oldFTSMatches.isEmpty)
      let newFTSMatches = try Int64.fetchAll(
        db,
        sql: "SELECT rowid FROM podcast_fts WHERE podcast_fts MATCH 'Updated'"
      )
      #expect(newFTSMatches == [800])
    }
  }
}
