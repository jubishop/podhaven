// Copyright Justin Bishop, 2026

import FactoryKit
import Foundation
import GRDB
import Testing

@testable import PodHaven

@Suite("of v56 migration tests", .container)
class V56MigrationTests {
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

  // MARK: - Filter Conversion

  @Test("v56 converts each row's nested group into a groups array")
  func convertsNestedToGroups() async throws {
    try migrator.migrate(appDB.unsafeTestDB, upTo: "v55")

    try await appDB.unsafeTestDB.write { db in
      try Self.insertFilter(
        db,
        title: "WithNested",
        filter:
          #"{"combinator":"all","conditions":[{"kind":"state","value":"isCached"}],"nested":{"combinator":"any","conditions":[{"kind":"state","value":"isLoved"},{"kind":"state","value":"isLiked"}]}}"#,
        order: 90
      )
      try Self.insertFilter(
        db,
        title: "NullNested",
        filter: #"{"combinator":"all","conditions":[],"nested":null}"#,
        order: 91
      )
      try Self.insertFilter(
        db,
        title: "AbsentNested",
        filter: #"{"combinator":"any","conditions":[{"kind":"state","value":"isQueued"}]}"#,
        order: 92
      )
    }

    try migrator.migrate(appDB.unsafeTestDB, upTo: "v56")

    let filters = try await appDB.unsafeTestDB.read { db -> [String: String] in
      Dictionary(
        uniqueKeysWithValues: try Row.fetchAll(db, sql: "SELECT title, filter FROM smartList")
          .map { ($0["title"], $0["filter"]) }
      )
    }

    // Every row now carries a groups array and no nested key.
    for filter in filters.values {
      let object = try JSONSerialization.jsonObject(with: Data(filter.utf8)) as? [String: Any]
      let json = try #require(object)
      #expect(json["combinator"] is String)
      #expect(json["conditions"] is [Any])
      #expect(json["groups"] is [Any])
      #expect(!json.keys.contains("nested"))
    }

    // The nested object lands intact as the array's single element.
    let withNested = try JSONSerialization.jsonObject(
      with: Data(try #require(filters["WithNested"]).utf8)
    )
    let groups = try #require((withNested as? [String: Any])?["groups"] as? [[String: Any]])
    #expect(groups.count == 1)
    #expect(groups[0]["combinator"] as? String == "any")
    #expect((groups[0]["conditions"] as? [Any])?.count == 2)

    // Null and absent nested groups both become empty arrays.
    for title in ["NullNested", "AbsentNested"] {
      let object = try JSONSerialization.jsonObject(with: Data(try #require(filters[title]).utf8))
      #expect(((object as? [String: Any])?["groups"] as? [Any])?.isEmpty == true)
    }

    // The 10 seeds are converted along with everything else.
    let seedGroups = try await appDB.unsafeTestDB.read { db in
      try Int.fetchOne(
        db,
        sql: """
          SELECT COUNT(*) FROM smartList
          WHERE json_type(filter, '$.groups') IS 'array' AND displayOrder < 10
          """
      ) ?? 0
    }
    #expect(seedGroups == 10)
  }

  @Test("v56 preserves row identity and columns through the rebuild")
  func preservesRowsThroughRebuild() async throws {
    try migrator.migrate(appDB.unsafeTestDB, upTo: "v55")

    try await appDB.unsafeTestDB.write { db in
      try db.execute(
        sql: """
          INSERT INTO smartList (title, filter, displayOrder, sortMethod, creationDate)
          VALUES ('Pinned', '{"combinator":"all","conditions":[],"nested":null}', 50,
                  'recentlyAdded', '2026-01-02 03:04:05')
          """
      )
    }
    let pinnedID = try await appDB.unsafeTestDB.read { db in
      try Int64.fetchOne(db, sql: "SELECT id FROM smartList WHERE title = 'Pinned'")
    }

    try migrator.migrate(appDB.unsafeTestDB, upTo: "v56")

    let row = try await appDB.unsafeTestDB.read { db -> (Int64, Int, String, String)? in
      guard
        let row = try Row.fetchOne(
          db,
          sql: """
            SELECT id, displayOrder, sortMethod, creationDate
            FROM smartList WHERE title = 'Pinned'
            """
        )
      else { return nil }
      return (row["id"], row["displayOrder"], row["sortMethod"], row["creationDate"])
    }
    let pinned = try #require(row)
    #expect(pinned.0 == pinnedID)
    #expect(pinned.1 == 50)
    #expect(pinned.2 == "recentlyAdded")
    #expect(pinned.3 == "2026-01-02 03:04:05")

    let count = try await appDB.unsafeTestDB.read { db in
      try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM smartList") ?? 0
    }
    #expect(count == 11)

    let indexExists = try await appDB.unsafeTestDB.read { db in
      try Bool.fetchOne(
        db,
        sql:
          "SELECT EXISTS(SELECT 1 FROM sqlite_master WHERE type='index' AND name='smartList_on_displayOrder')"
      ) ?? false
    }
    #expect(indexExists)
  }

  // MARK: - CHECK Constraints

  @Test("v56 filter CHECK requires a groups array")
  func filterJSONCheck() async throws {
    try migrator.migrate(appDB.unsafeTestDB, upTo: "v56")

    // Accepted: empty and populated groups arrays.
    try await appDB.unsafeTestDB.write { db in
      try Self.insertFilter(
        db,
        title: "Empty",
        filter: #"{"combinator":"all","conditions":[],"groups":[]}"#,
        order: 90
      )
      try Self.insertFilter(
        db,
        title: "TwoGroups",
        filter:
          #"{"combinator":"all","conditions":[],"groups":[{"combinator":"any","conditions":[]},{"combinator":"all","conditions":[]}]}"#,
        order: 91
      )
    }

    // Rejected: non-JSON, missing required keys (including the pre-v56 nested
    // shape, which lacks groups), and a non-array groups value.
    let rejected: [(title: String, filter: String)] = [
      ("Garbage", "not json at all"),
      ("Array", "[]"),
      ("NoCombinator", #"{"conditions":[],"groups":[]}"#),
      ("NoConditions", #"{"combinator":"all","groups":[]}"#),
      ("NoGroups", #"{"combinator":"all","conditions":[]}"#),
      ("LegacyNested", #"{"combinator":"all","conditions":[],"nested":null}"#),
      ("NullGroups", #"{"combinator":"all","conditions":[],"groups":null}"#),
      ("BadGroups", #"{"combinator":"all","conditions":[],"groups":5}"#),
    ]
    for (index, row) in rejected.enumerated() {
      await #expect(throws: DatabaseError.self) {
        try await self.appDB.unsafeTestDB.write { db in
          try Self.insertFilter(db, title: row.title, filter: row.filter, order: 100 + index)
        }
      }
    }
  }

  @Test("v56 keeps the sortMethod CHECK on the rebuilt table")
  func sortMethodCheck() async throws {
    try migrator.migrate(appDB.unsafeTestDB, upTo: "v56")

    try await appDB.unsafeTestDB.write { db in
      try db.execute(
        sql: """
          INSERT INTO smartList (title, filter, displayOrder, sortMethod)
          VALUES ('Recs', '{"combinator":"all","conditions":[],"groups":[]}', 99, 'recommendationScore')
          """
      )
    }

    await #expect(throws: DatabaseError.self) {
      try await self.appDB.unsafeTestDB.write { db in
        try db.execute(
          sql: """
            INSERT INTO smartList (title, filter, displayOrder, sortMethod)
            VALUES ('Bad', '{"combinator":"all","conditions":[],"groups":[]}', 100, 'bogusSort')
            """
        )
      }
    }
  }
}
