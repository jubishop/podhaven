// Copyright Justin Bishop, 2026

import FactoryKit
import Foundation
import GRDB
import Testing

@testable import PodHaven

@Suite("of v60 migration tests", .container)
class V60MigrationTests {
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

  @Test("v60 rewrites the equals operator to contains in top and nested groups")
  func rewritesEquals() async throws {
    let literalInput =
      #"{"combinator":"all","conditions":[{"kind":"episodeText","field":"title","op":"contains","value":"equals"}],"groups":[]}"#

    try migrator.migrate(appDB.unsafeTestDB, upTo: "v59")
    try await appDB.unsafeTestDB.write { db in
      try Self.insertFilter(
        db,
        title: "Equals",
        filter:
          #"{"combinator":"all","conditions":[{"kind":"episodeText","field":"title","op":"equals","value":"The"}],"groups":[{"combinator":"any","conditions":[{"kind":"podcastText","field":"description","op":"equals","value":"Bonus"}]}]}"#,
        order: 90
      )
      try Self.insertFilter(db, title: "LiteralValue", filter: literalInput, order: 91)
    }

    try migrator.migrate(appDB.unsafeTestDB, upTo: "v60")

    let filters = try await appDB.unsafeTestDB.read { db -> [String: String] in
      Dictionary(
        uniqueKeysWithValues:
          try Row.fetchAll(
            db,
            sql: "SELECT title, filter FROM smartList WHERE title IN ('Equals', 'LiteralValue')"
          )
          .map { ($0["title"], $0["filter"]) }
      )
    }

    // Both the top-level and nested equals operators become contains, and no
    // equals operator token remains (neither value held that substring).
    let rewritten = try #require(filters["Equals"])
    #expect(!rewritten.contains(#""op":"equals""#))
    #expect(rewritten.components(separatedBy: #""op":"contains""#).count - 1 == 2)

    // A contains value that happens to equal the operator name is untouched.
    #expect(filters["LiteralValue"] == literalInput)
  }
}
