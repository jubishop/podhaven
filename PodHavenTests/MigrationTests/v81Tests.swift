// Copyright Justin Bishop, 2026

import GRDB
import Testing

@testable import PodHaven

@Suite("of v81 migration tests", .container)
struct V81MigrationTests {
  private let appDB = AppDB.inMemory(migrate: false)
  private let migrator = Schema.makeMigrator()

  @Test("v81 gives queued transcription work a durable mode")
  func addsDurableTranscriptionWorkMode() async throws {
    try migrator.migrate(appDB.unsafeTestDB, upTo: "v80")
    try await appDB.unsafeTestDB.write { db in
      try db.execute(
        sql: """
          INSERT INTO podcast (
            id, feedURL, title, image, description
          ) VALUES (
            810, 'https://example.com/v81.xml', 'Replacement Mode',
            'https://example.com/v81.jpg', 'Description'
          )
          """
      )
      try db.execute(
        sql: """
          INSERT INTO episode (
            id, podcastId, guid, mediaURL, title, pubDate
          ) VALUES (
            811, 810, 'v81-1', 'https://example.com/v81-1.mp3',
            'Existing Queue Entry', '2026-01-01 00:00:00'
          )
          """
      )
      try db.execute(
        sql: """
          INSERT INTO episodeTranscriptionQueue (episodeId)
          VALUES (811)
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
          WHERE episodeId = 811
          """
      )
    }
    #expect(workMode == "publisherPreferred")
  }
}
