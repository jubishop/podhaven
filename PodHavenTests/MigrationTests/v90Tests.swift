// Copyright Justin Bishop, 2026

import GRDB
import Testing

@testable import PodHaven

@Suite("of v90 migration tests", .container)
struct V90MigrationTests {
  private let appDB = AppDB.inMemory(migrate: false)
  private let migrator = Schema.makeMigrator()

  @Test("v90 clears every embedding failure and keeps the episodes")
  func clearsEmbeddingFailures() async throws {
    try migrator.migrate(appDB.unsafeTestDB, upTo: "v89")
    try await appDB.unsafeTestDB.write { db in
      try db.execute(
        sql: """
          INSERT INTO podcast (id, feedURL, title, image, description)
          VALUES (
            900, 'https://example.com/v90.xml', 'Failure Reset',
            'https://example.com/v90.jpg', 'Description'
          )
          """
      )
      try db.execute(
        sql: """
          INSERT INTO episode (id, podcastId, guid, mediaURL, title, pubDate, description)
          VALUES
            (901, 900, 'quarantined', 'https://example.com/901.mp3', '12:30',
              '2026-01-01 00:00:00', 'Embeddable description'),
            (902, 900, 'retrying', 'https://example.com/902.mp3', 'Retrying',
              '2026-01-02 00:00:00', 'Description'),
            (903, 900, 'healthy', 'https://example.com/903.mp3', 'Healthy',
              '2026-01-03 00:00:00', 'Description')
          """
      )
      try db.execute(
        sql: """
          INSERT INTO episodeEmbeddingFailure (
            episodeId, episodeContentUpdatedAt, podcastContentUpdatedAt,
            embeddingRevision, recipeVersion, attemptCount
          )
          SELECT
            episode.id, episode.contentUpdatedAt, podcast.contentUpdatedAt, 4, 5,
            CASE episode.id WHEN 901 THEN 3 ELSE 1 END
          FROM episode
          JOIN podcast ON podcast.id = episode.podcastId
          WHERE episode.id IN (901, 902)
          """
      )
    }

    try migrator.migrate(appDB.unsafeTestDB)

    try await appDB.unsafeTestDB.read { db in
      #expect(try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM episodeEmbeddingFailure") == 0)
      let rows = try Row.fetchAll(
        db,
        sql: "SELECT id, title, description FROM episode ORDER BY id"
      )
      #expect(rows.map { $0["id"] as Int } == [901, 902, 903])
      #expect(rows.map { $0["title"] as String } == ["12:30", "Retrying", "Healthy"])
      #expect(
        rows.map { $0["description"] as String }
          == ["Embeddable description", "Description", "Description"]
      )
    }
  }
}
