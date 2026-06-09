// Copyright Justin Bishop, 2026

import FactoryKit
import Foundation
import GRDB
import Testing

@testable import PodHaven

@Suite("of v51 migration tests", .container)
class V51MigrationTests {
  private let appDB = AppDB.inMemory(migrate: false)
  private let migrator: DatabaseMigrator

  init() async throws {
    self.migrator = Schema.makeMigrator()
  }

  private var defaults: FakeKeyValueStore {
    Container.shared.standardDefaults() as! FakeKeyValueStore
  }

  private static let expectedTitles = [
    "Recent Episodes", "Unqueued", "Cached", "Saved", "Finished",
    "Unfinished", "Previously Queued", "Liked", "Disliked", "Not Interested",
  ]

  // MARK: - Schema & Seeds

  @Test("v51 creates, indexes, and seeds the smartList table")
  func createsIndexesAndSeeds() async throws {
    try migrator.migrate(appDB.unsafeTestDB, upTo: "v51")

    let rows = try await appDB.unsafeTestDB.read { db -> [(String, Int, String, String)] in
      try Row.fetchAll(
        db,
        sql: "SELECT title, displayOrder, filter, sortMethod FROM smartList ORDER BY displayOrder"
      )
      .map { ($0["title"], $0["displayOrder"], $0["filter"], $0["sortMethod"]) }
    }

    #expect(rows.map(\.0) == Self.expectedTitles)
    #expect(rows.map(\.1) == Array(0..<10))
    // No UserDefaults prefs set, so every row defaults to newestFirst.
    #expect(rows.allSatisfy { $0.3 == "newestFirst" })

    // Each filter is valid JSON with the documented shape.
    for row in rows {
      let object = try JSONSerialization.jsonObject(with: Data(row.2.utf8)) as? [String: Any]
      let json = try #require(object)
      #expect(json["combinator"] is String)
      #expect(json["conditions"] is [Any])
      #expect(json.keys.contains("nested"))
    }

    let indexExists = try await appDB.unsafeTestDB.read { db in
      try Bool.fetchOne(
        db,
        sql:
          "SELECT EXISTS(SELECT 1 FROM sqlite_master WHERE type='index' AND name='smartList_displayOrder')"
      ) ?? false
    }
    #expect(indexExists)
  }

  @Test("v51 sortMethod CHECK accepts recommendationScore and rejects unknown values")
  func sortMethodCheck() async throws {
    try migrator.migrate(appDB.unsafeTestDB, upTo: "v51")

    try await appDB.unsafeTestDB.write { db in
      try db.execute(
        sql: """
          INSERT INTO smartList (title, filter, displayOrder, sortMethod)
          VALUES ('Recs', '{"combinator":"all","conditions":[],"nested":null}', 99, 'recommendationScore')
          """
      )
    }

    await #expect(throws: DatabaseError.self) {
      try await self.appDB.unsafeTestDB.write { db in
        try db.execute(
          sql: """
            INSERT INTO smartList (title, filter, displayOrder, sortMethod)
            VALUES ('Bad', '{"combinator":"all","conditions":[],"nested":null}', 100, 'bogusSort')
            """
        )
      }
    }
  }

  @Test("v51 filter CHECK enforces the SmartListFilter top-level shape")
  func filterJSONCheck() async throws {
    try migrator.migrate(appDB.unsafeTestDB, upTo: "v51")

    func insertFilter(_ title: String, _ filter: String, order: Int) async throws {
      try await appDB.unsafeTestDB.write { db in
        try db.execute(
          sql:
            "INSERT INTO smartList (title, filter, displayOrder, sortMethod) VALUES (?, ?, ?, 'newestFirst')",
          arguments: [title, filter, order]
        )
      }
    }

    // Accepted: a well-formed object, and one that omits the optional nested key.
    try await insertFilter(
      "Valid",
      #"{"combinator":"all","conditions":[],"nested":null}"#,
      order: 90
    )
    try await insertFilter("NoNested", #"{"combinator":"all","conditions":[]}"#, order: 91)

    // Rejected: non-JSON, non-object JSON, missing required keys, wrong nested type —
    // all of which satisfy json_valid but the SmartListFilter decoder cannot read.
    let rejected: [(title: String, filter: String)] = [
      ("Garbage", "not json at all"),
      ("String", #""justastring""#),
      ("Array", "[]"),
      ("NoCombinator", #"{"conditions":[],"nested":null}"#),
      ("NoConditions", #"{"combinator":"all","nested":null}"#),
      ("BadNested", #"{"combinator":"all","conditions":[],"nested":5}"#),
    ]
    for (index, row) in rejected.enumerated() {
      await #expect(throws: DatabaseError.self) {
        try await insertFilter(row.title, row.filter, order: 100 + index)
      }
    }
  }

  // MARK: - Sort-Pref Copy (keys retained)

  @Test("v51 copies UserDefaults sort prefs onto rows without deleting the keys")
  func copiesSortPrefsWithoutDeletingKeys() async throws {
    try migrator.migrate(appDB.unsafeTestDB, upTo: "v50")

    defaults.set(Data(#""recentlyAdded""#.utf8), forKey: "EpisodesList-sortMethod-Liked")
    defaults.set(Data("not-json".utf8), forKey: "EpisodesList-sortMethod-Finished")
    defaults.set(Data(#""oldestFirst""#.utf8), forKey: "EpisodesList-sortMethod-SomeUserList")

    try migrator.migrate(appDB.unsafeTestDB, upTo: "v51")

    let sorts = try await appDB.unsafeTestDB.read { db -> [String: String] in
      Dictionary(
        uniqueKeysWithValues: try Row.fetchAll(db, sql: "SELECT title, sortMethod FROM smartList")
          .map { ($0["title"], $0["sortMethod"]) }
      )
    }
    #expect(sorts["Liked"] == "recentlyAdded")  // carried over
    #expect(sorts["Finished"] == "newestFirst")  // garbage rejected, defaulted

    // Phase 1 copies but does NOT delete the keys (the old VM still reads them).
    #expect(defaults.data(forKey: "EpisodesList-sortMethod-Liked") != nil)
    #expect(defaults.data(forKey: "EpisodesList-sortMethod-Finished") != nil)
    // Unrelated keys are untouched.
    #expect(
      defaults.data(forKey: "EpisodesList-sortMethod-SomeUserList") == Data(#""oldestFirst""#.utf8)
    )
  }

  // MARK: - Pre-existing data

  @Test("v51 leaves v50 data intact")
  func leavesV50DataIntact() async throws {
    try migrator.migrate(appDB.unsafeTestDB, upTo: "v50")
    try await appDB.unsafeTestDB.write { db in
      try db.execute(
        sql: """
          INSERT INTO podcast (feedURL, title, image, description)
          VALUES ('https://feed', 'T', 'img', 'desc')
          """
      )
    }

    try migrator.migrate(appDB.unsafeTestDB, upTo: "v51")

    let podcastCount = try await appDB.unsafeTestDB.read { db in
      try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM podcast") ?? 0
    }
    #expect(podcastCount == 1)
  }
}
