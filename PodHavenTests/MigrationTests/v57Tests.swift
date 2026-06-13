// Copyright Justin Bishop, 2026

import FactoryKit
import Foundation
import GRDB
import Testing

@testable import PodHaven

@Suite("of v57 migration tests", .container)
class V57MigrationTests {
  private let appDB = AppDB.inMemory(migrate: false)
  private let migrator: DatabaseMigrator

  init() async throws {
    self.migrator = Schema.makeMigrator()
  }

  @Test("v57 adds alwaysShowPodcastImage defaulting existing rows to false")
  func backfillsExistingRows() async throws {
    try migrator.migrate(appDB.unsafeTestDB, upTo: "v56")

    try await appDB.unsafeTestDB.write { db in
      try db.execute(
        sql: """
          INSERT INTO smartList (title, filter, displayOrder, sortMethod)
          VALUES ('Existing', '{"combinator":"all","conditions":[],"groups":[]}', 50, 'newestFirst')
          """
      )
    }

    try migrator.migrate(appDB.unsafeTestDB, upTo: "v57")

    // Every pre-existing row (the 10 seeds plus the inserted one) backfills to 0.
    let nonFalse = try await appDB.unsafeTestDB.read { db in
      try Int.fetchOne(
        db,
        sql: "SELECT COUNT(*) FROM smartList WHERE alwaysShowPodcastImage <> 0"
      ) ?? -1
    }
    #expect(nonFalse == 0)
  }

  @Test("v57 lets new rows opt into alwaysShowPodcastImage")
  func acceptsTrueValue() async throws {
    try migrator.migrate(appDB.unsafeTestDB, upTo: "v57")

    try await appDB.unsafeTestDB.write { db in
      try db.execute(
        sql: """
          INSERT INTO smartList (title, filter, displayOrder, sortMethod, alwaysShowPodcastImage)
          VALUES ('Podcast Art', '{"combinator":"all","conditions":[],"groups":[]}', 99,
                  'newestFirst', 1)
          """
      )
    }

    let value = try await appDB.unsafeTestDB.read { db in
      try Bool.fetchOne(
        db,
        sql: "SELECT alwaysShowPodcastImage FROM smartList WHERE title = 'Podcast Art'"
      )
    }
    #expect(value == true)
  }
}
