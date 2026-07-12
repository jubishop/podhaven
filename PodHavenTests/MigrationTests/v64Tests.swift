// Copyright Justin Bishop, 2026

import Foundation
import GRDB
import Testing

@testable import PodHaven

@Suite("of v64 migration tests", .container)
class V64MigrationTests {
  private let appDB = AppDB.inMemory(migrate: false)
  private let migrator: DatabaseMigrator

  init() async throws {
    self.migrator = Schema.makeMigrator()
  }

  @Test("v64 upgrades each untouched seeded default to a themed icon")
  func upgradesSeededDefaults() async throws {
    try migrator.migrate(appDB.unsafeTestDB, upTo: "v63")

    // The v54 seed plus the v62 backfill leaves every default on list-music.
    let before = try await appDB.unsafeTestDB.read { db in
      try String.fetchAll(db, sql: "SELECT icon FROM smartList")
    }
    #expect(before.count == 10)
    #expect(before.allSatisfy { $0 == "list-music" })

    try migrator.migrate(appDB.unsafeTestDB, upTo: "v64")

    let expected: [String: String] = [
      "Recent Episodes": "sparkles",
      "Unqueued": "inbox",
      "Cached": "download",
      "Saved": "bookmark",
      "Finished": "circle-check",
      "Unfinished": "hourglass",
      "Previously Queued": "history",
      "Liked": "heart",
      "Disliked": "frown",
      "Not Interested": "meh",
    ]
    let icons = try await appDB.unsafeTestDB.read { db in
      try Row.fetchAll(db, sql: "SELECT title, icon FROM smartList")
        .reduce(into: [String: String]()) { $0[$1["title"]] = $1["icon"] }
    }
    #expect(icons == expected)
  }

  @Test("v64 leaves a default whose icon was already customized")
  func skipsCustomizedIcon() async throws {
    try migrator.migrate(appDB.unsafeTestDB, upTo: "v63")

    // Same title and filter as the Cached default, but the user already picked
    // an icon, so it is no longer on the default list-music.
    try await appDB.unsafeTestDB.write { db in
      try db.execute(
        sql: """
          INSERT INTO smartList (title, filter, displayOrder, sortMethod, lastSeenEpisodeId, icon)
          VALUES ('Cached', '{"combinator":"all","conditions":[{"kind":"state","value":"isCached"}],"groups":[]}', 50, 'newestFirst', 0, 'cpu')
          """
      )
    }
    let id = try await appDB.unsafeTestDB.read { db in
      try Int.fetchOne(db, sql: "SELECT id FROM smartList WHERE icon = 'cpu'")
    }

    try migrator.migrate(appDB.unsafeTestDB, upTo: "v64")

    let icon = try await appDB.unsafeTestDB.read { db in
      try String.fetchOne(db, sql: "SELECT icon FROM smartList WHERE id = ?", arguments: [id])
    }
    #expect(icon == "cpu")
  }

  @Test("v64 leaves a list whose filter was edited away from the default")
  func skipsEditedFilter() async throws {
    try migrator.migrate(appDB.unsafeTestDB, upTo: "v63")

    // The default Cached title and icon, but an extra condition was added, so
    // the filter no longer matches the seeded default.
    try await appDB.unsafeTestDB.write { db in
      try db.execute(
        sql: """
          INSERT INTO smartList (title, filter, displayOrder, sortMethod, lastSeenEpisodeId, icon)
          VALUES ('Cached', '{"combinator":"all","conditions":[{"kind":"state","value":"isCached"},{"kind":"state","value":"isSaved"}],"groups":[]}', 50, 'newestFirst', 0, 'list-music')
          """
      )
    }
    let id = try await appDB.unsafeTestDB.read { db in
      try Int.fetchOne(db, sql: "SELECT id FROM smartList WHERE displayOrder = 50")
    }

    try migrator.migrate(appDB.unsafeTestDB, upTo: "v64")

    let icon = try await appDB.unsafeTestDB.read { db in
      try String.fetchOne(db, sql: "SELECT icon FROM smartList WHERE id = ?", arguments: [id])
    }
    #expect(icon == "list-music")
  }

  @Test("v64 leaves a renamed list on the default icon")
  func skipsRenamedTitle() async throws {
    try migrator.migrate(appDB.unsafeTestDB, upTo: "v63")

    // A renamed list that still carries the default Cached filter and icon; the
    // rename means it is no longer a recognized default.
    try await appDB.unsafeTestDB.write { db in
      try db.execute(
        sql: """
          INSERT INTO smartList (title, filter, displayOrder, sortMethod, lastSeenEpisodeId, icon)
          VALUES ('Offline', '{"combinator":"all","conditions":[{"kind":"state","value":"isCached"}],"groups":[]}', 50, 'newestFirst', 0, 'list-music')
          """
      )
    }

    try migrator.migrate(appDB.unsafeTestDB, upTo: "v64")

    let icon = try await appDB.unsafeTestDB.read { db in
      try String.fetchOne(db, sql: "SELECT icon FROM smartList WHERE title = 'Offline'")
    }
    #expect(icon == "list-music")
  }
}
