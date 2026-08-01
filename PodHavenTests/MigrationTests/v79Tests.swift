// Copyright Justin Bishop, 2026

import GRDB
import Testing

@testable import PodHaven

@Suite("of v79 migration tests", .container)
struct V79MigrationTests {
  private let appDB = AppDB.inMemory(migrate: false)
  private let migrator = Schema.makeMigrator()

  @Test("v79 adds nullable publisher transcript reference and source storage")
  func addsPublisherTranscriptMetadataColumns() async throws {
    try migrator.migrate(appDB.unsafeTestDB, upTo: "v77")
    try await appDB.unsafeTestDB.write { db in
      try db.execute(
        sql: """
          INSERT INTO podcast (
            id, feedURL, title, image, description
          ) VALUES (
            790, 'https://example.com/v79.xml', 'Publisher Transcript',
            'https://example.com/v79.jpg', 'Description'
          )
          """
      )
      try db.execute(
        sql: """
          INSERT INTO episode (
            id, podcastId, guid, mediaURL, title, pubDate, transcript
          ) VALUES (
            791, 790, 'v79-1', 'https://example.com/v79-1.mp3',
            'Existing Episode', '2026-01-01 00:00:00',
            '{"segments":[{"start":0,"end":1,"text":"Existing"}]}'
          )
          """
      )
    }

    let columnsBefore = try await appDB.unsafeTestDB.read { db in
      try db.columns(in: "episode").map(\.name)
    }
    #expect(!columnsBefore.contains("publisherTranscriptReferencesJSON"))
    #expect(!columnsBefore.contains("publisherTranscriptSourceJSON"))

    try migrator.migrate(appDB.unsafeTestDB, upTo: "v79")

    let metadata = try await appDB.unsafeTestDB.read { db in
      let columns = try db.columns(in: "episode").map(\.name)
      let row = try Row.fetchOne(
        db,
        sql: """
          SELECT transcript, publisherTranscriptReferencesJSON,
                 publisherTranscriptSourceJSON
          FROM episode
          WHERE id = 791
          """
      )
      let transcript: String? = row?["transcript"]
      let references: String? = row?["publisherTranscriptReferencesJSON"]
      let source: String? = row?["publisherTranscriptSourceJSON"]
      return (columns, transcript, references, source)
    }
    #expect(metadata.0.contains("publisherTranscriptReferencesJSON"))
    #expect(metadata.0.contains("publisherTranscriptSourceJSON"))
    #expect(metadata.1 != nil)
    #expect(metadata.2 == nil)
    #expect(metadata.3 == nil)
  }
}
