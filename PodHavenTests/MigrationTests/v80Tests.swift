// Copyright Justin Bishop, 2026

import GRDB
import Testing

@testable import PodHaven

@Suite("of v80 migration tests", .container)
struct V80MigrationTests {
  private let appDB = AppDB.inMemory(migrate: false)
  private let migrator = Schema.makeMigrator()

  @Test("v80 creates empty cascading publisher transcript work without backfill")
  func createsEmptyCascadingWorkWithoutBackfill() async throws {
    try migrator.migrate(appDB.unsafeTestDB, upTo: "v79")
    try await appDB.unsafeTestDB.write { db in
      try db.execute(
        sql: """
          INSERT INTO podcast (
            id, feedURL, title, image, description
          ) VALUES (
            800, 'https://example.com/v80.xml', 'Publisher Work',
            'https://example.com/v80.jpg', 'Description'
          )
          """
      )
      try db.execute(
        sql: """
          INSERT INTO episode (
            id, podcastId, guid, mediaURL, title, pubDate,
            publisherTranscriptReferencesJSON
          ) VALUES (
            801, 800, 'v80-1', 'https://example.com/v80-1.mp3',
            'Historical Episode', '2026-01-01 00:00:00',
            '[{"url":"https://example.com/v80.vtt","type":"text/vtt"}]'
          )
          """
      )
    }

    try migrator.migrate(appDB.unsafeTestDB, upTo: "v80")

    let initialCount = try await appDB.unsafeTestDB.read { db in
      try Int.fetchOne(
        db,
        sql: "SELECT COUNT(*) FROM publisherTranscriptImportJob"
      )
    }
    #expect(initialCount == 0)

    try await appDB.unsafeTestDB.write { db in
      try db.execute(
        sql: """
          INSERT INTO publisherTranscriptImportJob (
            episodeId, attemptCount, nextAttemptAt
          ) VALUES (801, 0, '2026-01-01 00:00:00')
          """
      )
      try db.execute(sql: "DELETE FROM episode WHERE id = 801")
    }

    let countAfterEpisodeDeletion = try await appDB.unsafeTestDB.read { db in
      try Int.fetchOne(
        db,
        sql: "SELECT COUNT(*) FROM publisherTranscriptImportJob"
      )
    }
    #expect(countAfterEpisodeDeletion == 0)
  }
}
