// Copyright Justin Bishop, 2026

import Foundation
import GRDB
import Testing

@testable import PodHaven

@Suite("of v62 migration tests", .container)
class V62MigrationTests {
  private let appDB = AppDB.inMemory(migrate: false)
  private let migrator: DatabaseMigrator

  init() async throws {
    self.migrator = Schema.makeMigrator()
  }

  // MARK: - Fixture

  private func seedEpisodeAtV61() async throws {
    try migrator.migrate(appDB.unsafeTestDB, upTo: "v61")

    try await appDB.unsafeTestDB.write { db in
      try db.execute(
        sql: """
          INSERT INTO podcast (
            id, feedURL, title, image, description, link, lastUpdate,
            subscriptionDate, creationDate, defaultPlaybackRate,
            queueAllEpisodes, cacheAllEpisodes, notifyNewEpisodes, iTunesID,
            contentUpdatedAt
          ) VALUES (
            700, 'https://example.com/v62.xml', 'V62 Podcast',
            'https://example.com/img.jpg', 'Description',
            NULL, '2024-01-01 00:00:00', NULL, '2024-01-01 00:00:00',
            1.0, 'never', 'never', 0, NULL, '2024-01-01 00:00:00'
          )
          """
      )
      try db.execute(
        sql: """
          INSERT INTO episode (
            id, podcastId, guid, mediaURL, title, pubDate, creationDate,
            contentUpdatedAt, currentTime, maxPlaybackTime, saveInCache,
            downloading
          ) VALUES (
            710, 700, 'guid-1', 'https://example.com/ep1.mp3',
            'Episode One', '2024-02-01 00:00:00', '2024-02-01 00:00:00',
            '2024-02-01 00:00:00', 0, 0, 0, 0
          )
          """
      )
    }
  }

  @Test("v62 adds a nullable transcript column, NULL for existing episodes")
  func addsNullableTranscriptColumn() async throws {
    try await seedEpisodeAtV61()

    try migrator.migrate(appDB.unsafeTestDB, upTo: "v62")

    let transcript = try await appDB.unsafeTestDB.read { db in
      try String.fetchOne(db, sql: "SELECT transcript FROM episode WHERE id = 710")
    }
    #expect(transcript == nil)
  }

  @Test("v62 stores timed-segment transcript JSON")
  func storesTranscriptJSON() async throws {
    try await seedEpisodeAtV61()
    try migrator.migrate(appDB.unsafeTestDB, upTo: "v62")

    let json =
      #"{"segments":[{"start":0,"text":"Hello"}],"locale":"en-US","createdAt":760000000,"modelRevision":1}"#
    try await appDB.unsafeTestDB.write { db in
      try db.execute(
        sql: """
          INSERT INTO episode (
            id, podcastId, guid, mediaURL, title, pubDate, creationDate,
            contentUpdatedAt, currentTime, maxPlaybackTime, saveInCache,
            downloading, transcript
          ) VALUES (
            711, 700, 'guid-2', 'https://example.com/ep2.mp3',
            'Episode Two', '2024-02-02 00:00:00', '2024-02-02 00:00:00',
            '2024-02-02 00:00:00', 0, 0, 0, 0, ?
          )
          """,
        arguments: [json]
      )
    }

    let stored = try await appDB.unsafeTestDB.read { db in
      try String.fetchOne(db, sql: "SELECT transcript FROM episode WHERE id = 711")
    }
    #expect(stored == json)
  }
}
