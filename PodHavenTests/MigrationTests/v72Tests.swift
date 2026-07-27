// Copyright Justin Bishop, 2026

import GRDB
import Testing

@testable import PodHaven

@Suite("of v72 migration tests", .container)
struct V72MigrationTests {
  private let appDB = AppDB.inMemory(migrate: false)
  private let migrator: DatabaseMigrator

  init() async throws {
    migrator = Schema.makeMigrator()
  }

  @Test("v72 adds showUnreadBadge defaulting existing rows to true")
  func backfillsExistingRows() async throws {
    try migrator.migrate(appDB.unsafeTestDB, upTo: "v71")

    try await appDB.unsafeTestDB.write { db in
      try db.execute(
        sql: """
          INSERT INTO smartList (title, filter, displayOrder, sortMethod)
          VALUES ('Existing', '{"combinator":"all","conditions":[],"groups":[]}', 50, 'newestFirst')
          """
      )
    }

    try migrator.migrate(appDB.unsafeTestDB, upTo: "v72")

    let notEnabled = try await appDB.unsafeTestDB.read { db in
      try Int.fetchOne(
        db,
        sql: "SELECT COUNT(*) FROM smartList WHERE showUnreadBadge IS NOT 1"
      ) ?? -1
    }
    #expect(notEnabled == 0)
  }

  @Test("v72 lets a smart list hide its unread badge")
  func acceptsFalseValue() async throws {
    try migrator.migrate(appDB.unsafeTestDB, upTo: "v72")

    try await appDB.unsafeTestDB.write { db in
      try db.execute(
        sql: """
          INSERT INTO smartList (
            title, filter, displayOrder, sortMethod, showUnreadBadge
          ) VALUES (
            'Hidden Badge', '{"combinator":"all","conditions":[],"groups":[]}',
            99, 'newestFirst', 0
          )
          """
      )
    }

    let value = try await appDB.unsafeTestDB.read { db in
      try Bool.fetchOne(
        db,
        sql: "SELECT showUnreadBadge FROM smartList WHERE title = 'Hidden Badge'"
      )
    }
    #expect(value == false)
  }
}
