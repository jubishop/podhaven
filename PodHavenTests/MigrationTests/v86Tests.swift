// Copyright Justin Bishop, 2026

import GRDB
import Testing

@testable import PodHaven

@Suite("of v86 migration tests", .container)
struct V86MigrationTests {
  private let appDB = AppDB.inMemory(migrate: false)
  private let migrator = Schema.makeMigrator()

  @Test("v86 adds empty feed validator columns to existing podcasts")
  func addsFeedValidatorColumns() async throws {
    try migrator.migrate(appDB.unsafeTestDB, upTo: "v85")
    try await appDB.unsafeTestDB.write { db in
      try db.execute(
        sql: """
          INSERT INTO podcast (id, feedURL, title, image, description)
          VALUES (
            860, 'https://example.com/v86.xml', 'Validator Show',
            'https://example.com/v86.jpg', 'Description'
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
            FROM podcast WHERE id = 860
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
          WHERE id = 860
          """
      )
      #expect(
        try String.fetchOne(db, sql: "SELECT feedETag FROM podcast WHERE id = 860") == "\"v1\""
      )
    }
  }
}
