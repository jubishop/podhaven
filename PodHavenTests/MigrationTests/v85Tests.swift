// Copyright Justin Bishop, 2026

import GRDB
import Testing

@testable import PodHaven

@Suite("of v85 migration tests", .container)
struct V85MigrationTests {
  private let appDB = AppDB.inMemory(migrate: false)
  private let migrator = Schema.makeMigrator()

  @Test("v85 moves finish state from the library revision to its own revision")
  func separatesFinishRevision() async throws {
    try migrator.migrate(appDB.unsafeTestDB, upTo: "v84")
    try await appDB.unsafeTestDB.write { db in
      try db.execute(
        sql: """
          INSERT INTO podcast (
            id, feedURL, title, image, description
          ) VALUES (
            850, 'https://example.com/v85.xml', 'Revision Show',
            'https://example.com/v85.jpg', 'Description'
          );
          INSERT INTO episode (
            id, podcastId, guid, mediaURL, title, pubDate
          ) VALUES (
            851, 850, 'v85-1', 'https://example.com/v85-1.mp3',
            'Revision Episode', '2026-01-01 00:00:00'
          )
          """
      )
    }
    let revision = try await appDB.unsafeTestDB.read { db in
      try Int64.fetchOne(db, sql: "SELECT revision FROM siriCatalogRevision")
    }

    try migrator.migrate(appDB.unsafeTestDB)

    try await appDB.unsafeTestDB.write { (db: Database) throws in
      #expect(try Int64.fetchOne(db, sql: "SELECT revision FROM siriCatalogRevision") == revision)
      #expect(try String.fetchOne(db, sql: "SELECT title FROM episode WHERE id = 851") != nil)
      func changes(_ sql: String) throws -> (Bool, Bool) {
        let query = "SELECT revision, finishRevision FROM siriCatalogRevision"
        let before = try Row.fetchOne(db, sql: query)
        try db.execute(sql: sql)
        let after = try Row.fetchOne(db, sql: query)
        return (
          before?["revision"] as Int64? != after?["revision"],
          before?["finishRevision"] as Int64? != after?["finishRevision"]
        )
      }
      #expect(try changes("UPDATE episode SET finishDate = '2026-01-02 00:00:00'") == (false, true))
      #expect(try changes("UPDATE episode SET title = 'Renamed Episode'") == (true, false))
      #expect(try changes("UPDATE episode SET pubDate = '2026-01-03 00:00:00'") == (true, false))
      #expect(try changes("UPDATE episode SET currentTime = 30") == (false, false))
      #expect(try changes("UPDATE podcast SET title = 'Renamed Show'") == (true, false))
      #expect(
        try changes(
          """
          INSERT INTO episode (id, podcastId, guid, mediaURL, title, pubDate)
          VALUES (852, 850, 'v85-2', 'https://example.com/v85-2.mp3', 'Second', '2026-01-04 00:00:00')
          """
        ) == (true, false)
      )
      #expect(try changes("DELETE FROM episode WHERE id = 852") == (true, false))
    }
  }
}
