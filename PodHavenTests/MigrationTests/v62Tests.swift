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

  @Test("v62 backfills existing tags and smart lists with default icons")
  func backfillsExistingRows() async throws {
    try migrator.migrate(appDB.unsafeTestDB, upTo: "v61")

    try await appDB.unsafeTestDB.write { db in
      try db.execute(sql: "INSERT INTO tag (name) VALUES ('Existing')")
      try db.execute(
        sql: """
          INSERT INTO smartList (title, filter, displayOrder, sortMethod, lastSeenEpisodeId)
          VALUES ('Existing', '{"combinator":"all","conditions":[],"groups":[]}', 50, 'newestFirst', 0)
          """
      )
    }

    try migrator.migrate(appDB.unsafeTestDB, upTo: "v62")

    let (tagIcon, listIcon) = try await appDB.unsafeTestDB.read { db in
      let tag = try String.fetchOne(db, sql: "SELECT icon FROM tag WHERE name = 'Existing'")
      let list = try String.fetchOne(
        db,
        sql: "SELECT icon FROM smartList WHERE title = 'Existing'"
      )
      return (tag, list)
    }
    #expect(tagIcon == "tag")
    #expect(listIcon == "list-music")
  }

  @Test("v62 lets new rows set an explicit icon")
  func acceptsExplicitIcon() async throws {
    try migrator.migrate(appDB.unsafeTestDB, upTo: "v62")

    try await appDB.unsafeTestDB.write { db in
      try db.execute(sql: "INSERT INTO tag (name, icon) VALUES ('Tech', 'cpu')")
    }

    let icon = try await appDB.unsafeTestDB.read { db in
      try String.fetchOne(db, sql: "SELECT icon FROM tag WHERE name = 'Tech'")
    }
    #expect(icon == "cpu")
  }
}
