// Copyright Justin Bishop, 2026

import GRDB
import Testing

@testable import PodHaven

@Suite("of v78 migration tests", .container)
struct V78MigrationTests {
  private let appDB = AppDB.inMemory(migrate: false)
  private let migrator = Schema.makeMigrator()

  private func prepareAtV77() async throws {
    try migrator.migrate(appDB.unsafeTestDB, upTo: "v77")
    try await appDB.unsafeTestDB.write { db in
      try db.execute(
        sql: """
          INSERT INTO podcast (
            id, feedURL, title, image, description
          ) VALUES (
            780, 'https://example.com/v78.xml', 'Timed Transcript',
            'https://example.com/v78.jpg', 'Description'
          )
          """
      )
      try db.execute(
        sql: """
          INSERT INTO episode (
            id, podcastId, guid, mediaURL, title, pubDate, transcript
          ) VALUES
            (
              781, 780, 'v78-1', 'https://example.com/v78-1.mp3',
              'Legacy Transcript', '2026-01-01 00:00:00',
              '{"segments":[{"start":0,"end":2,"text":"Legacy words"}],"locale":"en-US","createdAt":790000000}'
            ),
            (
              782, 780, 'v78-2', 'https://example.com/v78-2.mp3',
              'Malformed Transcript', '2026-01-02 00:00:00', 'not-json'
            )
          """
      )
      try db.execute(
        sql: """
          INSERT INTO episodeTranscriptionCheckpoint (
            episodeId, checkpointJSON
          ) VALUES (
            781,
            '{"segments":[{"start":0,"end":1,"text":"Partial"}],"audioTime":1,"duration":2,"locale":"en-US","audioSHA256":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"}'
          )
          """
      )
    }
  }

  @Test("v78 adds empty word timing arrays to existing transcript payloads")
  func addsWordTimingArrays() async throws {
    try await prepareAtV77()

    try migrator.migrate(appDB.unsafeTestDB, upTo: "v78")

    try await appDB.unsafeTestDB.read { db in
      let transcriptWordsType = try String.fetchOne(
        db,
        sql: "SELECT json_type(transcript, '$.segments[0].words') FROM episode WHERE id = 781"
      )
      let transcriptWordsCount = try Int.fetchOne(
        db,
        sql:
          "SELECT json_array_length(transcript, '$.segments[0].words') FROM episode WHERE id = 781"
      )
      let transcriptText = try String.fetchOne(
        db,
        sql: "SELECT json_extract(transcript, '$.segments[0].text') FROM episode WHERE id = 781"
      )
      let checkpointWordsType = try String.fetchOne(
        db,
        sql: """
          SELECT json_type(checkpointJSON, '$.segments[0].words')
          FROM episodeTranscriptionCheckpoint
          WHERE episodeId = 781
          """
      )
      let checkpointText = try String.fetchOne(
        db,
        sql: """
          SELECT json_extract(checkpointJSON, '$.segments[0].text')
          FROM episodeTranscriptionCheckpoint
          WHERE episodeId = 781
          """
      )
      let malformedTranscript = try String.fetchOne(
        db,
        sql: "SELECT transcript FROM episode WHERE id = 782"
      )

      #expect(transcriptWordsType == "array")
      #expect(transcriptWordsCount == 0)
      #expect(transcriptText == "Legacy words")
      #expect(checkpointWordsType == "array")
      #expect(checkpointText == "Partial")
      #expect(malformedTranscript == "not-json")
    }
  }
}
