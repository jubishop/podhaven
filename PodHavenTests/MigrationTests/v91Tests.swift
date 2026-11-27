// Copyright Justin Bishop, 2026

import GRDB
import Testing

@testable import PodHaven

@Suite("of v91 migration tests", .container)
struct V91MigrationTests {
  private let appDB = AppDB.inMemory(migrate: false)
  private let migrator = Schema.makeMigrator()

  @Test("v91 labels existing episode embeddings with recipe version 2")
  func labelsExistingEmbeddingsWithRecipeVersion() async throws {
    try migrator.migrate(appDB.unsafeTestDB, upTo: "v90")
    try await appDB.unsafeTestDB.write { db in
      try db.execute(
        sql: """
          INSERT INTO podcast (id, feedURL, title, image, description)
          VALUES (
            910, 'https://example.com/v91.xml', 'Recipe Show',
            'https://example.com/v91.jpg', 'Description'
          )
          """
      )
      try db.execute(
        sql: """
          INSERT INTO episode (id, podcastId, guid, mediaURL, title, pubDate, description)
          VALUES
            (911, 910, 'first', 'https://example.com/911.mp3', 'First',
              '2026-01-01 00:00:00', 'Description'),
            (912, 910, 'second', 'https://example.com/912.mp3', 'Second',
              '2026-01-02 00:00:00', 'Description')
          """
      )
      try db.execute(
        sql: """
          INSERT INTO episodeEmbedding (
            episodeId, vector, sourceHash, embeddingRevision, dimension
          ) VALUES
            (911, zeroblob(12), 'first-hash', 1, 3),
            (912, zeroblob(12), 'second-hash', 4, 3)
          """
      )
    }

    try migrator.migrate(appDB.unsafeTestDB)

    try await appDB.unsafeTestDB.write { db in
      let rows = try Row.fetchAll(
        db,
        sql: """
          SELECT episodeId, sourceHash, embeddingRevision, recipeVersion
          FROM episodeEmbedding ORDER BY episodeId
          """
      )
      #expect(rows.map { $0["episodeId"] as Int } == [911, 912])
      #expect(rows.map { $0["sourceHash"] as String } == ["first-hash", "second-hash"])
      #expect(rows.map { $0["embeddingRevision"] as Int } == [1, 4])
      #expect(rows.map { $0["recipeVersion"] as Int } == [2, 2])

      #expect(
        throws: DatabaseError.self,
        performing: {
          try db.execute(
            sql: "UPDATE episodeEmbedding SET recipeVersion = NULL WHERE episodeId = 911"
          )
        }
      )
    }
  }
}
