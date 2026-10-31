// Copyright Justin Bishop, 2026

import GRDB
import Testing

@testable import PodHaven

@Suite("of v84 migration tests", .container)
struct V84MigrationTests {
  private let appDB = AppDB.inMemory(migrate: false)
  private let migrator = Schema.makeMigrator()

  @Test("v84 keeps the library and replaces its revision with each catalog-relevant change")
  func addsLibraryRevision() async throws {
    try migrator.migrate(appDB.unsafeTestDB, upTo: "v83")
    try await appDB.unsafeTestDB.write { db in
      try db.execute(
        sql: """
          INSERT INTO podcast (
            id, feedURL, title, image, description
          ) VALUES (
            840, 'https://example.com/v84.xml', 'Revision Show',
            'https://example.com/v84.jpg', 'Description'
          );
          INSERT INTO episode (
            id, podcastId, guid, mediaURL, title, pubDate
          ) VALUES (
            841, 840, 'v84-1', 'https://example.com/v84-1.mp3',
            'Revision Episode', '2026-01-01 00:00:00'
          )
          """
      )
    }

    try migrator.migrate(appDB.unsafeTestDB)

    try await appDB.unsafeTestDB.write { (db: Database) throws in
      #expect(try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM siriCatalogRevision") == 1)
      #expect(try String.fetchOne(db, sql: "SELECT title FROM episode WHERE id = 841") != nil)
      func changes(_ sql: String) throws -> Bool {
        let before = try Int64.fetchOne(db, sql: "SELECT revision FROM siriCatalogRevision")
        try db.execute(sql: sql)
        return try Int64.fetchOne(db, sql: "SELECT revision FROM siriCatalogRevision") != before
      }
      #expect(try changes("UPDATE podcast SET title = 'Renamed Show'"))
      #expect(try changes("UPDATE podcast SET feedURL = 'https://example.com/v84-moved.xml'"))
      #expect(try !changes("UPDATE podcast SET description = 'Other'"))
      #expect(try changes("UPDATE episode SET finishDate = '2026-01-02 00:00:00'"))
      #expect(try !changes("UPDATE episode SET currentTime = 30"))
      #expect(
        try changes(
          """
          INSERT INTO episode (id, podcastId, guid, mediaURL, title, pubDate)
          VALUES (842, 840, 'v84-2', 'https://example.com/v84-2.mp3', 'Second', '2026-01-03 00:00:00')
          """
        )
      )
      #expect(try changes("DELETE FROM episode WHERE id = 842"))
      #expect(try changes("DELETE FROM podcast WHERE id = 840"))
      #expect(throws: DatabaseError.self) {
        try db.execute(sql: "INSERT INTO siriCatalogRevision (id, revision) VALUES (2, 0)")
      }
    }
  }
}
