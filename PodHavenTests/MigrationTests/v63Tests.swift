// Copyright Justin Bishop, 2026

import FactoryKit
import Foundation
import GRDB
import Testing

@testable import PodHaven

@Suite("of v63 migration tests", .container)
class V63MigrationTests {
  private let appDB = AppDB.inMemory(migrate: false)
  private let migrator: DatabaseMigrator

  private static let key = "SearchView-displayMode"

  init() async throws {
    self.migrator = Schema.makeMigrator()
  }

  private var defaults: FakeKeyValueStore {
    Container.shared.standardDefaults() as! FakeKeyValueStore
  }

  @Test("removes the orphaned search display-mode key")
  func testRemovesKey() async throws {
    try migrator.migrate(appDB.unsafeTestDB, upTo: "v62")
    defaults.set(Data(#""grid""#.utf8), forKey: Self.key)

    try migrator.migrate(appDB.unsafeTestDB, upTo: "v63")

    #expect(defaults.data(forKey: Self.key) == nil)
  }

  @Test("leaves the podcasts display-mode key untouched")
  func testLeavesUnrelatedKey() async throws {
    try migrator.migrate(appDB.unsafeTestDB, upTo: "v62")
    let value = Data(#""grid""#.utf8)
    defaults.set(value, forKey: "PodcastsList-displayMode")

    try migrator.migrate(appDB.unsafeTestDB, upTo: "v63")

    #expect(defaults.data(forKey: "PodcastsList-displayMode") == value)
  }

  @Test("is a no-op when the key is absent")
  func testNoOpWhenAbsent() async throws {
    try migrator.migrate(appDB.unsafeTestDB, upTo: "v62")

    try migrator.migrate(appDB.unsafeTestDB, upTo: "v63")

    #expect(defaults.data(forKey: Self.key) == nil)
  }
}
