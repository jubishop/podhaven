// Copyright Justin Bishop, 2026

import GRDB
import Testing

@testable import PodHaven

@Suite("of v80 migration tests", .container)
struct V80MigrationTests {
  private let appDB = AppDB.inMemory(migrate: false)
  private let migrator = Schema.makeMigrator()

  @Test("v80 gives queued transcription work a durable mode")
  func addsDurableTranscriptionWorkMode() async throws {
    try migrator.migrate(appDB.unsafeTestDB, upTo: "v79")
    try await appDB.unsafeTestDB.write { db in
      try db.execute(
        sql: """
          INSERT INTO podcast (
            id, feedURL, title, image, description
          ) VALUES (
            800, 'https://example.com/v80.xml', 'Replacement Mode',
            'https://example.com/v80.jpg', 'Description'
          )
          """
      )
      try db.execute(
        sql: """
          INSERT INTO episode (
            id, podcastId, guid, mediaURL, title, pubDate
          ) VALUES (
            801, 800, 'v80-1', 'https://example.com/v80-1.mp3',
            'Existing Queue Entry', '2026-01-01 00:00:00'
          )
          """
      )
      try db.execute(
        sql: """
          INSERT INTO episodeTranscriptionQueue (episodeId)
          VALUES (801)
          """
      )
    }

    try migrator.migrate(appDB.unsafeTestDB)

    let columns = try await appDB.unsafeTestDB.read { db in
      try db.columns(in: "episodeTranscriptionQueue").map(\.name)
    }
    #expect(columns.contains("workMode"))
    guard columns.contains("workMode") else { return }

    let workMode = try await appDB.unsafeTestDB.read { db in
      try String.fetchOne(
        db,
        sql: """
          SELECT workMode
          FROM episodeTranscriptionQueue
          WHERE episodeId = 801
          """
      )
    }
    #expect(workMode == "publisherPreferred")
  }
}
