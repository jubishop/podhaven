// Copyright Justin Bishop, 2026

import GRDB
import Testing

@testable import PodHaven

@Suite("of v87 migration tests", .container)
struct V87MigrationTests {
  private let appDB = AppDB.inMemory(migrate: false)
  private let migrator = Schema.makeMigrator()

  @Test("v87 adds empty feed validator columns to existing podcasts")
  func addsFeedValidatorColumns() async throws {
    try migrator.migrate(appDB.unsafeTestDB, upTo: "v86")
    try await appDB.unsafeTestDB.write { db in
      try db.execute(
        sql: """
          INSERT INTO podcast (id, feedURL, title, image, description)
          VALUES (
            870, 'https://example.com/v87.xml', 'Validator Show',
            'https://example.com/v87.jpg', 'Description'
          )
          """
      )
    }

    try migrator.migrate(appDB.unsafeTestDB)

    try await appDB.unsafeTestDB.write { db in
      let row = try #require(
        try Row.fetchOne(
          db,
          sql: """
            SELECT feedETag, feedLastModified, feedValidatorsBuild
            FROM podcast WHERE id = 870
            """
        )
      )
      #expect(row["feedETag"] as String? == nil)
      #expect(row["feedLastModified"] as String? == nil)
      #expect(row["feedValidatorsBuild"] as String? == nil)

      try db.execute(
        sql: """
          UPDATE podcast
          SET feedETag = '"v1"', feedLastModified = 'Wed, 21 Oct 2026 07:28:00 GMT',
            feedValidatorsBuild = '1.0 (abc1234)'
          WHERE id = 870
          """
      )
      #expect(
        try String.fetchOne(db, sql: "SELECT feedETag FROM podcast WHERE id = 870") == "\"v1\""
      )
    }
  }
}
