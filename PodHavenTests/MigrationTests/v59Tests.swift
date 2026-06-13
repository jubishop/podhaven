// Copyright Justin Bishop, 2026

import FactoryKit
import Foundation
import GRDB
import Testing

@testable import PodHaven

@Suite("of v59 migration tests", .container)
class V59MigrationTests {
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

  private func indexExists(_ name: String) async throws -> Bool {
    try await appDB.unsafeTestDB.read { db in
      try Bool.fetchOne(
        db,
        sql: "SELECT EXISTS(SELECT 1 FROM sqlite_master WHERE type='index' AND name=?)",
        arguments: [name]
      ) ?? false
    }
  }

  private func indexSQL(_ name: String) async throws -> String {
    try await appDB.unsafeTestDB.read { db in
      try String.fetchOne(
        db,
        sql: "SELECT sql FROM sqlite_master WHERE type='index' AND name=?",
        arguments: [name]
      ) ?? ""
    }
  }

  // MARK: - Indexes

  @Test("v59 adds sort and tag indexes and replaces the rating index")
  func addsIndexes() async throws {
    try migrator.migrate(appDB.unsafeTestDB, upTo: "v58")
    #expect(try await indexExists("episode_on_rating"))

    try migrator.migrate(appDB.unsafeTestDB, upTo: "v59")

    for name in [
      "episode_on_creationDate",
      "episode_on_duration",
      "episode_on_finishDate",
      "episode_on_queueDate",
      "episode_on_rating_pubDate",
      "episodeTag_on_tagId_episodeId",
      "podcastTag_on_tagId_podcastId",
    ] {
      #expect(try await indexExists(name))
    }

    // The rating-only partial index is replaced by the composite.
    #expect(try await indexExists("episode_on_rating") == false)

    // The non-null sorts stay partial; the rating composite spans both columns
    // and keeps its non-null guard.
    #expect(try await indexSQL("episode_on_finishDate").contains("WHERE"))
    #expect(try await indexSQL("episode_on_queueDate").contains("WHERE"))
    let ratingSQL = try await indexSQL("episode_on_rating_pubDate")
    #expect(ratingSQL.contains("rating"))
    #expect(ratingSQL.contains("pubDate"))
    #expect(ratingSQL.contains("WHERE"))
  }

  // MARK: - startsWith → contains

  @Test("v59 rewrites the startsWith operator to contains in top and nested groups")
  func rewritesStartsWith() async throws {
    let literalInput =
      #"{"combinator":"all","conditions":[{"kind":"episodeText","field":"title","op":"contains","value":"startsWith"}],"groups":[]}"#

    try migrator.migrate(appDB.unsafeTestDB, upTo: "v58")
    try await appDB.unsafeTestDB.write { db in
      try Self.insertFilter(
        db,
        title: "StartsWith",
        filter:
          #"{"combinator":"all","conditions":[{"kind":"episodeText","field":"title","op":"startsWith","value":"The"}],"groups":[{"combinator":"any","conditions":[{"kind":"podcastText","field":"description","op":"startsWith","value":"Bonus"}]}]}"#,
        order: 90
      )
      try Self.insertFilter(db, title: "LiteralValue", filter: literalInput, order: 91)
    }

    try migrator.migrate(appDB.unsafeTestDB, upTo: "v59")

    let filters = try await appDB.unsafeTestDB.read { db -> [String: String] in
      Dictionary(
        uniqueKeysWithValues: try Row.fetchAll(db, sql: "SELECT title, filter FROM smartList")
          .map { ($0["title"], $0["filter"]) }
      )
    }

    // Both the top-level and nested startsWith operators become contains, and no
    // startsWith token remains (neither value held that substring).
    let rewritten = try #require(filters["StartsWith"])
    #expect(!rewritten.contains("startsWith"))
    #expect(rewritten.components(separatedBy: #""op":"contains""#).count - 1 == 2)

    // A contains value that happens to equal the operator name is untouched.
    #expect(filters["LiteralValue"] == literalInput)
  }
}
