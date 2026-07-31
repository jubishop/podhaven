// Copyright Justin Bishop, 2026

import GRDB
import Testing

@testable import PodHaven

@Suite("of v76 migration tests", .container)
struct V76MigrationTests {
  private let appDB = AppDB.inMemory(migrate: false)
  private let migrator = Schema.makeMigrator()

  @Test("v76 adds alwaysTranscribeNewEpisodes defaulting existing podcasts to false")
  func defaultsExistingPodcastsToFalse() async throws {
    try migrator.migrate(appDB.unsafeTestDB, upTo: "v75")
    try await appDB.unsafeTestDB.write { db in
      try db.execute(
        sql: """
          INSERT INTO podcast (feedURL, title, image, description)
          VALUES (
            'https://example.com/v76.xml', 'Automatic Transcription',
            'https://example.com/v76.jpg', 'Description'
          )
          """
      )
    }

    try migrator.migrate(appDB.unsafeTestDB, upTo: "v76")

    let value = try await appDB.unsafeTestDB.read { db in
      try Bool.fetchOne(
        db,
        sql: """
          SELECT alwaysTranscribeNewEpisodes
          FROM podcast
          WHERE feedURL = 'https://example.com/v76.xml'
          """
      )
    }
    #expect(value == false)
  }

  @Test("v76 allows podcasts to opt into automatic transcription")
  func acceptsTrueValue() async throws {
    try migrator.migrate(appDB.unsafeTestDB, upTo: "v76")
    try await appDB.unsafeTestDB.write { db in
      try db.execute(
        sql: """
          INSERT INTO podcast (
            feedURL, title, image, description, alwaysTranscribeNewEpisodes
          ) VALUES (
            'https://example.com/v76-opt-in.xml', 'Opted In',
            'https://example.com/v76-opt-in.jpg', 'Description', 1
          )
          """
      )
    }

    let value = try await appDB.unsafeTestDB.read { db in
      try Bool.fetchOne(
        db,
        sql: """
          SELECT alwaysTranscribeNewEpisodes
          FROM podcast
          WHERE feedURL = 'https://example.com/v76-opt-in.xml'
          """
      )
    }
    #expect(value == true)
  }
}
