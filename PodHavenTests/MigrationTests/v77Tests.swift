// Copyright Justin Bishop, 2026

import GRDB
import Testing

@testable import PodHaven

@Suite("of v77 migration tests", .container)
struct V77MigrationTests {
  private let appDB = AppDB.inMemory(migrate: false)
  private let migrator = Schema.makeMigrator()

  private func prepareAtV76() async throws {
    try migrator.migrate(appDB.unsafeTestDB, upTo: "v76")
    try await appDB.unsafeTestDB.write { db in
      try db.execute(
        sql: """
          INSERT INTO podcast (
            id, feedURL, title, image, description
          ) VALUES (
            770, 'https://example.com/v77.xml', 'Transcript Search',
            'https://example.com/v77.jpg', 'Description'
          )
          """
      )
      try db.execute(
        sql: """
          INSERT INTO episode (
            id, podcastId, guid, mediaURL, title, pubDate, transcript
          ) VALUES
            (
              771, 770, 'v77-1', 'https://example.com/v77-1.mp3',
              'Matching Transcript', '2026-01-01 00:00:00', ?
            ),
            (
              772, 770, 'v77-2', 'https://example.com/v77-2.mp3',
              'No Transcript', '2026-01-02 00:00:00', NULL
            ),
            (
              773, 770, 'v77-3', 'https://example.com/v77-3.mp3',
              'Other Transcript', '2026-01-03 00:00:00', ?
            ),
            (
              774, 770, 'v77-4', 'https://example.com/v77-4.mp3',
              'Malformed Transcript', '2026-01-04 00:00:00', 'not-json'
            ),
            (
              775, 770, 'v77-5', 'https://example.com/v77-5.mp3',
              'Invalid Segments', '2026-01-05 00:00:00',
              '{"segments":["not-an-object"]}'
            )
          """,
        arguments: [
          """
          {"segments":[{"start":0,"end":1,"text":"The quantum"},\
          {"start":1,"end":2,"text":"physics hour"}]}
          """,
          """
          {"segments":[{"start":0,"end":1,"text":"Garden notes"}]}
          """,
        ]
      )
    }
  }

  private func matches(_ pattern: String) async throws -> [Int64] {
    try await appDB.unsafeTestDB.read { db in
      try Int64.fetchAll(
        db,
        sql: """
          SELECT rowid
          FROM episode_transcript_fts
          WHERE episode_transcript_fts MATCH ?
          ORDER BY rowid
          """,
        arguments: [pattern]
      )
    }
  }

  @Test("v77 backfills flattened transcript text without indexing JSON metadata")
  func backfillsFlattenedTranscriptText() async throws {
    try await prepareAtV76()

    let tableBefore = try await appDB.unsafeTestDB.read { db in
      try String.fetchOne(
        db,
        sql: "SELECT name FROM sqlite_master WHERE name = 'episode_transcript_fts'"
      )
    }
    #expect(tableBefore == nil)

    try migrator.migrate(appDB.unsafeTestDB, upTo: "v77")

    #expect(try await matches(#""quantum physics""#) == [771])
    #expect(try await matches("garden") == [773])
    #expect(try await matches("segments").isEmpty)
  }

  @Test("v77 transcript index tracks inserts, updates, nulling, and deletes")
  func triggersStayInSync() async throws {
    try await prepareAtV76()
    try migrator.migrate(appDB.unsafeTestDB, upTo: "v77")

    try await appDB.unsafeTestDB.write { db in
      try db.execute(
        sql: """
          INSERT INTO episode (
            id, podcastId, guid, mediaURL, title, pubDate, transcript
          ) VALUES (
            776, 770, 'v77-6', 'https://example.com/v77-6.mp3',
            'Inserted Transcript', '2026-01-06 00:00:00',
            '{"segments":[{"start":0,"end":1,"text":"Inserted phrase"}]}'
          )
          """
      )
    }
    #expect(try await matches(#""inserted phrase""#) == [776])

    try await appDB.unsafeTestDB.write { db in
      try db.execute(
        sql: "UPDATE episode SET transcript = ? WHERE id = 771",
        arguments: [#"{"segments":[{"start":0,"end":1,"text":"Ocean currents"}]}"#]
      )
    }
    #expect(try await matches("quantum").isEmpty)
    #expect(try await matches(#""ocean currents""#) == [771])

    try await appDB.unsafeTestDB.write { db in
      try db.execute(
        sql: "UPDATE episode SET transcript = ? WHERE id = 772",
        arguments: [#"{"segments":[{"start":0,"end":1,"text":"Mountain weather"}]}"#]
      )
    }
    #expect(try await matches(#""mountain weather""#) == [772])

    try await appDB.unsafeTestDB.write { db in
      try db.execute(sql: "UPDATE episode SET transcript = NULL WHERE id = 771")
      try db.execute(sql: "DELETE FROM episode WHERE id = 773")
    }
    #expect(try await matches("ocean").isEmpty)
    #expect(try await matches("garden").isEmpty)
  }
}
