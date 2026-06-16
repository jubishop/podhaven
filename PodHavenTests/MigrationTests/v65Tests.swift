// Copyright Justin Bishop, 2026

import Foundation
import GRDB
import Testing

@testable import PodHaven

@Suite("of v65 migration tests", .container)
class V65MigrationTests {
  private let appDB = AppDB.inMemory(migrate: false)
  private let migrator: DatabaseMigrator

  init() async throws {
    self.migrator = Schema.makeMigrator()
  }

  private static func insertFilter(_ db: Database, title: String, filter: String, order: Int)
    throws
  {
    try db.execute(
      sql:
        "INSERT INTO smartList (title, filter, displayOrder, sortMethod) VALUES (?, ?, ?, 'newestFirst')",
      arguments: [title, filter, order]
    )
  }

  @Test("v65 rewrites tag filters and preserves podcast text filters")
  func rewritesTagsAndPreservesPodcastText() async throws {
    try migrator.migrate(appDB.unsafeTestDB, upTo: "v64")

    try await appDB.unsafeTestDB.write { db in
      try Self.insertFilter(
        db,
        title: "Legacy",
        filter:
          #"{"combinator":"all","conditions":[{"kind":"podcastText","field":"title","op":"contains","value":"Tech"},{"kind":"episodeTag","tag":{"kind":"hasTag","tagID":1}},{"kind":"podcastTag","tag":{"kind":"doesNotHaveTag","tagID":2}},{"kind":"state","value":"isLoved"}],"groups":[{"combinator":"any","conditions":[{"kind":"podcastText","field":"description","op":"contains","value":"ads"},{"kind":"tag","tag":{"kind":"hasAnyTag"}}]},{"combinator":"all","conditions":[{"kind":"podcastText","field":"titleOrDescription","op":"contains","value":"noise"}]},{"combinator":"any","conditions":[{"kind":"podcastTag","tag":{"kind":"hasNoTags"}}]}]}"#,
        order: 90
      )
    }

    try migrator.migrate(appDB.unsafeTestDB, upTo: "v65")

    let filter = try await appDB.unsafeTestDB.read { db in
      try String.fetchOne(db, sql: "SELECT filter FROM smartList WHERE title = 'Legacy'")
    }
    #expect(
      filter
        == #"{"combinator":"all","conditions":[{"kind":"podcastText","field":"title","op":"contains","value":"Tech"},{"kind":"tag","tag":{"kind":"hasTag","tagID":1}},{"kind":"tag","tag":{"kind":"doesNotHaveTag","tagID":2}},{"kind":"state","value":"isLoved"}],"groups":[{"combinator":"any","conditions":[{"kind":"podcastText","field":"description","op":"contains","value":"ads"},{"kind":"tag","tag":{"kind":"hasAnyTag"}}]},{"combinator":"all","conditions":[{"kind":"podcastText","field":"titleOrDescription","op":"contains","value":"noise"}]},{"combinator":"any","conditions":[{"kind":"tag","tag":{"kind":"hasNoTags"}}]}]}"#
    )
  }

  @Test("v65 leaves podcast-text-only filters intact")
  func podcastTextOnlyFilterIsPreserved() async throws {
    try migrator.migrate(appDB.unsafeTestDB, upTo: "v64")

    try await appDB.unsafeTestDB.write { db in
      try Self.insertFilter(
        db,
        title: "Only Podcast Text",
        filter:
          #"{"combinator":"any","conditions":[{"kind":"podcastText","field":"title","op":"contains","value":"Tech"}],"groups":[{"combinator":"all","conditions":[{"kind":"podcastText","field":"description","op":"contains","value":"ads"}]}]}"#,
        order: 91
      )
    }

    try migrator.migrate(appDB.unsafeTestDB, upTo: "v65")

    let filter = try await appDB.unsafeTestDB.read { db in
      try String.fetchOne(
        db,
        sql: "SELECT filter FROM smartList WHERE title = 'Only Podcast Text'"
      )
    }
    #expect(
      filter
        == #"{"combinator":"any","conditions":[{"kind":"podcastText","field":"title","op":"contains","value":"Tech"}],"groups":[{"combinator":"all","conditions":[{"kind":"podcastText","field":"description","op":"contains","value":"ads"}]}]}"#
    )
  }
}
