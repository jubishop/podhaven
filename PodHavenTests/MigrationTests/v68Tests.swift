// Copyright Justin Bishop, 2026

import GRDB
import Testing

@testable import PodHaven

@Suite("of v68 migration tests", .container)
class V68MigrationTests {
  private let appDB = AppDB.inMemory(migrate: false)
  private let migrator: DatabaseMigrator

  init() async throws {
    self.migrator = Schema.makeMigrator()
  }

  @Test("v68 makes podcast title changes invalidate embeddings")
  func podcastTitleChangesAdvanceContentUpdatedAt() async throws {
    try migrator.migrate(appDB.unsafeTestDB, upTo: "v67")
    try await appDB.unsafeTestDB.write { db in
      try db.execute(
        sql: """
          INSERT INTO podcast (
            id, feedURL, title, image, description, link, lastUpdate,
            subscriptionDate, creationDate, defaultPlaybackRate,
            queueAllEpisodes, cacheAllEpisodes, notifyNewEpisodes, iTunesID,
            contentUpdatedAt
          ) VALUES (
            800, 'https://example.com/v68.xml', 'Original Title',
            'https://example.com/img.jpg', 'Description', NULL,
            '2024-01-01 00:00:00', NULL, '2024-01-01 00:00:00',
            1.0, 'never', 'never', 0, NULL, '2024-01-01 00:00:00'
          )
          """
      )
    }

    try migrator.migrate(appDB.unsafeTestDB)
    try await appDB.unsafeTestDB.write { db in
      try db.execute(sql: "UPDATE podcast SET title = 'Updated Title' WHERE id = 800")
    }

    let contentUpdatedAt = try await appDB.unsafeTestDB.read { db in
      try String.fetchOne(
        db,
        sql: "SELECT contentUpdatedAt FROM podcast WHERE id = 800"
      )
    }
    #expect(contentUpdatedAt != "2024-01-01 00:00:00")

    let indexedPodcastID = try await appDB.unsafeTestDB.read { db in
      try Int64.fetchOne(
        db,
        sql: "SELECT rowid FROM podcast_fts WHERE podcast_fts MATCH 'Updated'"
      )
    }
    #expect(indexedPodcastID == 800)
  }
}
