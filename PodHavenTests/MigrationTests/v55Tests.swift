// Copyright Justin Bishop, 2026

import FactoryKit
import Foundation
import GRDB
import Testing

@testable import PodHaven

@Suite("of v55 migration tests", .container)
class V55MigrationTests {
  private let appDB = AppDB.inMemory(migrate: false)
  private let migrator: DatabaseMigrator

  init() async throws {
    self.migrator = Schema.makeMigrator()
  }

  private func defaults() throws -> FakeKeyValueStore {
    try #require(Container.shared.standardDefaults() as? FakeKeyValueStore)
  }

  private func sortMethods() async throws -> [String: String] {
    try await appDB.unsafeTestDB.read { db in
      Dictionary(
        uniqueKeysWithValues: try Row.fetchAll(db, sql: "SELECT title, sortMethod FROM smartList")
          .map { ($0["title"], $0["sortMethod"]) }
      )
    }
  }

  @Test("v55 re-copies a surviving sort pref onto its row by title and deletes the key")
  func recopiesAndDeletesKey() async throws {
    try migrator.migrate(appDB.unsafeTestDB, upTo: "v54")
    // Planted after the v54 copy, like a sort change made between the releases.
    let defaults = try defaults()
    defaults.set(Data(#""recentlyAdded""#.utf8), forKey: "EpisodesList-sortMethod-Liked")

    try migrator.migrate(appDB.unsafeTestDB, upTo: "v55")

    let sorts = try await sortMethods()
    #expect(sorts["Liked"] == "recentlyAdded")
    #expect(defaults.data(forKey: "EpisodesList-sortMethod-Liked") == nil)
  }

  @Test("v55 discards an undecodable pref without touching the row")
  func garbagePrefDiscarded() async throws {
    try migrator.migrate(appDB.unsafeTestDB, upTo: "v54")
    let defaults = try defaults()
    defaults.set(Data("not json at all".utf8), forKey: "EpisodesList-sortMethod-Finished")

    try migrator.migrate(appDB.unsafeTestDB, upTo: "v55")

    let sorts = try await sortMethods()
    #expect(sorts["Finished"] == "newestFirst")
    #expect(defaults.data(forKey: "EpisodesList-sortMethod-Finished") == nil)
  }

  @Test("v55 discards a pref whose value is not an allowed sort method")
  func unknownSortMethodDiscarded() async throws {
    try migrator.migrate(appDB.unsafeTestDB, upTo: "v54")
    let defaults = try defaults()
    defaults.set(Data(#""bogusSort""#.utf8), forKey: "EpisodesList-sortMethod-Liked")

    try migrator.migrate(appDB.unsafeTestDB, upTo: "v55")

    let sorts = try await sortMethods()
    #expect(sorts["Liked"] == "newestFirst")
    #expect(defaults.data(forKey: "EpisodesList-sortMethod-Liked") == nil)
  }

  @Test("v55 deletes a pref with no matching row and leaves unrelated keys untouched")
  func unmatchedTitleAndUnrelatedKeys() async throws {
    try migrator.migrate(appDB.unsafeTestDB, upTo: "v54")
    let defaults = try defaults()
    defaults.set(Data(#""oldestFirst""#.utf8), forKey: "EpisodesList-sortMethod-No Such List")
    defaults.set(Data("unrelated".utf8), forKey: "SomeOtherSetting")

    try migrator.migrate(appDB.unsafeTestDB, upTo: "v55")

    #expect(defaults.data(forKey: "EpisodesList-sortMethod-No Such List") == nil)
    #expect(defaults.data(forKey: "SomeOtherSetting") == Data("unrelated".utf8))
  }
}
