// Copyright Justin Bishop, 2026

import GRDB
import Testing

@testable import PodHaven

@Suite("of v70 migration tests", .container)
struct V70MigrationTests {
  private let appDB = AppDB.inMemory(migrate: false)
  private let migrator: DatabaseMigrator

  init() async throws {
    migrator = Schema.makeMigrator()
  }

  private func prepareFixture() async throws {
    try migrator.migrate(appDB.unsafeTestDB, upTo: "v69")
    try await appDB.unsafeTestDB.write { db in
      try db.execute(
        sql: """
          INSERT INTO podcast (
            id, feedURL, title, image, description
          ) VALUES (
            900, 'https://example.com/v70.xml', 'Checkpoint',
            'https://example.com/v70.jpg', 'Description'
          )
          """
      )
      try db.execute(
        sql: """
          INSERT INTO episode (
            id, podcastId, guid, mediaURL, title, pubDate, description
          ) VALUES (
            901, 900, 'v70-episode', 'https://example.com/v70.mp3',
            'Episode', '2026-01-01 00:00:00', 'Description'
          )
          """
      )
    }
  }

  private func insertCheckpoint() async throws {
    try await appDB.unsafeTestDB.write { db in
      try db.execute(
        sql: """
          INSERT INTO episodeTranscriptionCheckpoint (
            episodeId, checkpointJSON
          ) VALUES (
            901,
            '{"segments":[{"start":0,"text":"First"}],"audioTime":120,"duration":7200,"locale":"en-US","modelRevision":2,"audioSHA256":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"}'
          )
          """
      )
    }
  }

  @Test("v70 creates durable per-episode transcription checkpoints")
  func createsTranscriptionCheckpoint() async throws {
    try await prepareFixture()
    #expect(
      try await appDB.unsafeTestDB.read { db in
        try db.tableExists("episodeTranscriptionCheckpoint")
      } == false
    )

    try migrator.migrate(appDB.unsafeTestDB, upTo: "v70")
    try await insertCheckpoint()

    try await appDB.unsafeTestDB.read { db in
      let columns = try db.columns(in: "episodeTranscriptionCheckpoint").map(\.name)
      #expect(columns == ["episodeId", "checkpointJSON"])

      let row = try #require(
        try Row.fetchOne(
          db,
          sql: """
            SELECT checkpointJSON
            FROM episodeTranscriptionCheckpoint
            WHERE episodeId = 901
            """
        )
      )
      let checkpointJSON: String = row["checkpointJSON"]
      #expect(checkpointJSON.contains("\"audioTime\":120"))
      #expect(
        checkpointJSON.contains(
          "\"audioSHA256\":\"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\""
        )
      )
    }
  }

  @Test("v70 rejects malformed transcription checkpoints")
  func rejectsMalformedCheckpoint() async throws {
    try await prepareFixture()
    try migrator.migrate(appDB.unsafeTestDB, upTo: "v70")

    await #expect(throws: DatabaseError.self) {
      try await self.appDB.unsafeTestDB.write { db in
        try db.execute(
          sql: """
            INSERT INTO episodeTranscriptionCheckpoint (
              episodeId, checkpointJSON
            ) VALUES (
              901,
              '{"segments":[],"audioTime":120,"duration":7200,"locale":"en-US","modelRevision":2}'
            )
            """
        )
      }
    }
  }

  @Test("v70 transcription checkpoints cascade with their episode")
  func transcriptionCheckpointCascades() async throws {
    try await prepareFixture()
    try migrator.migrate(appDB.unsafeTestDB, upTo: "v70")
    try await insertCheckpoint()

    try await appDB.unsafeTestDB.write { db in
      try db.execute(sql: "DELETE FROM episode WHERE id = 901")
    }

    let checkpointCount = try await appDB.unsafeTestDB.read { db in
      try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM episodeTranscriptionCheckpoint")
    }
    #expect(checkpointCount == 0)
  }
}
