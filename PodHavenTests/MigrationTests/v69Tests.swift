// Copyright Justin Bishop, 2026

import GRDB
import Testing

@testable import PodHaven

@Suite("of v69 migration tests", .container)
struct V69MigrationTests {
  private let appDB = AppDB.inMemory(migrate: false)
  private let migrator: DatabaseMigrator

  init() async throws {
    migrator = Schema.makeMigrator()
  }

  private func prepareFixture() async throws {
    try migrator.migrate(appDB.unsafeTestDB, upTo: "v68")
    try await appDB.unsafeTestDB.write { db in
      try db.execute(
        sql: """
          INSERT INTO podcast (
            id, feedURL, title, image, description
          ) VALUES (
            900, 'https://example.com/v69.xml', 'Failure State',
            'https://example.com/v69.jpg', 'Description'
          )
          """
      )
      try db.execute(
        sql: """
          INSERT INTO episode (
            id, podcastId, guid, mediaURL, title, pubDate, description
          ) VALUES (
            901, 900, 'v69-episode', 'https://example.com/v69.mp3',
            'Episode', '2026-01-01 00:00:00', 'Description'
          )
          """
      )
    }
  }

  private func insertFailure(attemptCount: Int = 3) async throws {
    try await appDB.unsafeTestDB.write { db in
      try db.execute(
        sql: """
          INSERT INTO episodeEmbeddingFailure (
            episodeId, episodeContentUpdatedAt, podcastContentUpdatedAt,
            embeddingRevision, recipeVersion, attemptCount
          )
          SELECT
            episode.id, episode.contentUpdatedAt, podcast.contentUpdatedAt,
            4, 5, ?
          FROM episode
          JOIN podcast ON podcast.id = episode.podcastId
          WHERE episode.id = 901
          """,
        arguments: [attemptCount]
      )
    }
  }

  @Test("v69 creates durable per-episode embedding failure state")
  func createsEmbeddingFailureState() async throws {
    try await prepareFixture()
    #expect(
      try await appDB.unsafeTestDB.read { db in
        try db.tableExists("episodeEmbeddingFailure")
      } == false
    )

    try migrator.migrate(appDB.unsafeTestDB, upTo: "v69")
    try await insertFailure()

    try await appDB.unsafeTestDB.read { db in
      let columns = try db.columns(in: "episodeEmbeddingFailure").map(\.name)
      #expect(
        columns == [
          "episodeId",
          "episodeContentUpdatedAt",
          "podcastContentUpdatedAt",
          "embeddingRevision",
          "recipeVersion",
          "attemptCount",
        ]
      )
      let row = try #require(
        try Row.fetchOne(
          db,
          sql: "SELECT * FROM episodeEmbeddingFailure WHERE episodeId = 901"
        )
      )
      #expect(row["embeddingRevision"] as Int == 4)
      #expect(row["recipeVersion"] as Int == 5)
      #expect(row["attemptCount"] as Int == 3)
    }

    await #expect(throws: DatabaseError.self) {
      try await self.appDB.unsafeTestDB.write { db in
        try db.execute(
          sql: """
            UPDATE episodeEmbeddingFailure
            SET attemptCount = 0
            WHERE episodeId = 901
            """
        )
      }
    }
  }

  @Test("v69 embedding failure state cascades with its episode")
  func embeddingFailureStateCascades() async throws {
    try await prepareFixture()
    try migrator.migrate(appDB.unsafeTestDB, upTo: "v69")
    try await insertFailure()

    try await appDB.unsafeTestDB.write { db in
      try db.execute(sql: "DELETE FROM episode WHERE id = 901")
    }

    let failureCount = try await appDB.unsafeTestDB.read { db in
      try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM episodeEmbeddingFailure")
    }
    #expect(failureCount == 0)
  }
}
