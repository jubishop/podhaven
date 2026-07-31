// Copyright Justin Bishop, 2026

import GRDB
import Testing

@testable import PodHaven

@Suite("of v76 migration tests", .container)
struct V76MigrationTests {
  private let appDB = AppDB.inMemory(migrate: false)
  private let migrator = Schema.makeMigrator()

  private func prepareAtV75() async throws {
    try migrator.migrate(appDB.unsafeTestDB, upTo: "v75")
    try await appDB.unsafeTestDB.write { db in
      try db.execute(
        sql: """
          INSERT INTO podcast (
            id, feedURL, title, image, description
          ) VALUES (
            760, 'https://example.com/v76.xml', 'Transcript Search',
            'https://example.com/v76.jpg', 'Description'
          )
          """
      )
      try db.execute(
        sql: """
          INSERT INTO episode (
            id, podcastId, guid, mediaURL, title, pubDate, transcript
          ) VALUES
            (
              761, 760, 'v76-1', 'https://example.com/v76-1.mp3',
              'Matching Transcript', '2026-01-01 00:00:00', ?
            ),
            (
              762, 760, 'v76-2', 'https://example.com/v76-2.mp3',
              'No Transcript', '2026-01-02 00:00:00', NULL
            ),
            (
              763, 760, 'v76-3', 'https://example.com/v76-3.mp3',
              'Other Transcript', '2026-01-03 00:00:00', ?
            ),
            (
              764, 760, 'v76-4', 'https://example.com/v76-4.mp3',
              'Malformed Transcript', '2026-01-04 00:00:00', 'not-json'
            ),
            (
              765, 760, 'v76-5', 'https://example.com/v76-5.mp3',
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

  @Test("v76 backfills flattened transcript text without indexing JSON metadata")
  func backfillsFlattenedTranscriptText() async throws {
    try await prepareAtV75()

    let tableBefore = try await appDB.unsafeTestDB.read { db in
      try String.fetchOne(
        db,
        sql: "SELECT name FROM sqlite_master WHERE name = 'episode_transcript_fts'"
      )
    }
    #expect(tableBefore == nil)

    try migrator.migrate(appDB.unsafeTestDB, upTo: "v76")

    #expect(try await matches(#""quantum physics""#) == [761])
    #expect(try await matches("garden") == [763])
    #expect(try await matches("segments").isEmpty)
  }

  @Test("v76 transcript index tracks inserts, updates, nulling, and deletes")
  func triggersStayInSync() async throws {
    try await prepareAtV75()
    try migrator.migrate(appDB.unsafeTestDB, upTo: "v76")

    try await appDB.unsafeTestDB.write { db in
      try db.execute(
        sql: "UPDATE episode SET transcript = ? WHERE id = 761",
        arguments: [#"{"segments":[{"start":0,"end":1,"text":"Ocean currents"}]}"#]
      )
    }
    #expect(try await matches("quantum").isEmpty)
    #expect(try await matches(#""ocean currents""#) == [761])

    try await appDB.unsafeTestDB.write { db in
      try db.execute(
        sql: "UPDATE episode SET transcript = ? WHERE id = 762",
        arguments: [#"{"segments":[{"start":0,"end":1,"text":"Mountain weather"}]}"#]
      )
    }
    #expect(try await matches(#""mountain weather""#) == [762])

    try await appDB.unsafeTestDB.write { db in
      try db.execute(sql: "UPDATE episode SET transcript = NULL WHERE id = 761")
      try db.execute(sql: "DELETE FROM episode WHERE id = 763")
    }
    #expect(try await matches("ocean").isEmpty)
    #expect(try await matches("garden").isEmpty)
  }
}
